//
//  SyncQueueService.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class SyncQueueService: ObservableObject {
    static let shared = SyncQueueService()

    @Published private(set) var isProcessing = false

    var hasActiveWork: Bool {
        isProcessing || !queue.isEmpty
    }

    private let apiClient = RambleAPIClient.shared
    private let storageService = StorageService.shared
    private var queue: [UploadJob] = []
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("sync_queue.json")

    private init() {
        loadQueue()
    }

    // MARK: - Public API

    func enqueue(recordingId: UUID) {
        // Don't double-enqueue
        guard !queue.contains(where: { $0.recordingId == recordingId }) else { return }
        let job = UploadJob(recordingId: recordingId)
        queue.append(job)
        saveQueue()
        processNextIfNeeded()
    }

    func processNextIfNeeded() {
        guard !isProcessing, let job = queue.first else { return }
        processJob(job)
    }

    func resumePendingJobs() {
        // Re-enqueue any recordings stuck in recorded/uploading state
        let recordings = storageService.loadRecordings()
        for recording in recordings {
            if recording.status == .recorded || recording.status == .uploading {
                enqueue(recordingId: recording.id)
            }
        }
        processNextIfNeeded()
    }

    /// Manually retry a failed recording by re-enqueuing it
    func retry(recordingId: UUID) {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        recordings[idx].status = .recorded
        recordings[idx].lastError = nil
        storageService.saveRecordings(recordings)

        // Remove any existing job for this recording before re-enqueuing
        queue.removeAll { $0.recordingId == recordingId }
        saveQueue()

        enqueue(recordingId: recordingId)
    }

    func job(for recordingId: UUID) -> UploadJob? {
        queue.first { $0.recordingId == recordingId }
    }

    // MARK: - Job Processing

    private func processJob(_ job: UploadJob) {
        isProcessing = true

        Task {
            switch job.phase {
            case .upload:
                await processUpload(job)
            case .poll:
                await processPoll(job)
            }
        }
    }

    private func processUpload(_ job: UploadJob) async {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) else {
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Update status to uploading
        recordings[idx].status = .uploading
        storageService.saveRecordings(recordings)

        let audioURL = recordings[idx].audioFileURL
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            recordings[idx].status = .failed
            recordings[idx].lastError = "Audio file not found"
            storageService.saveRecordings(recordings)
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        do {
            let audioData = try Data(contentsOf: audioURL)
            let params = RambleAPIClient.UploadParams(
                recording: recordings[idx],
                audioData: audioData
            )
            _ = try await apiClient.uploadRecording(params: params)

            // Upload succeeded — transition to poll phase
            var updatedJob = job
            updatedJob.phase = .poll
            updatedJob.retryCount = 0
            updatedJob.nextRetryAt = nil
            updateJob(updatedJob)

            // Update recording status
            var updatedRecordings = storageService.loadRecordings()
            if let i = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[i].status = .processing
                updatedRecordings[i].lastError = nil
                storageService.saveRecordings(updatedRecordings)
            }

            isProcessing = false

            // Brief delay before first poll
            try? await Task.sleep(nanoseconds: UInt64(3 * 1_000_000_000))
            processNextIfNeeded()

        } catch let error as APIError where error is APIError {
            await handleUploadFailure(job: job, error: error.localizedDescription ?? String(describing: error))
        } catch {
            await handleUploadFailure(job: job, error: error.localizedDescription)
        }
    }

    private func handleUploadFailure(job: UploadJob, error: String) async {
        print("Upload failed: \(error)")

        var updatedJob = job
        updatedJob.retryCount += 1

        var recordings = storageService.loadRecordings()
        if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
            recordings[idx].lastError = error
            if updatedJob.retryCount >= UploadJob.maxUploadRetries {
                recordings[idx].status = .failed
                storageService.saveRecordings(recordings)
                removeJob(job)
            } else {
                recordings[idx].status = .recorded
                let delay = updatedJob.retryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                storageService.saveRecordings(recordings)
                updateJob(updatedJob)
                print("Upload retry \(updatedJob.retryCount)/\(UploadJob.maxUploadRetries) in \(Int(delay))s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        isProcessing = false
        processNextIfNeeded()
    }

    private func processPoll(_ job: UploadJob) async {
        do {
            let response = try await apiClient.getRecording(id: job.recordingId)

            switch response.status {
            case "completed":
                // Update recording with results
                var recordings = storageService.loadRecordings()
                if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                    recordings[idx].status = .completed
                    recordings[idx].transcription = response.transcription
                    recordings[idx].agentNotes = response.agent_notes
                    recordings[idx].lastError = nil
                    storageService.saveRecordings(recordings)
                }
                removeJob(job)
                isProcessing = false
                processNextIfNeeded()

            case "failed":
                var recordings = storageService.loadRecordings()
                if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                    recordings[idx].status = .failed
                    recordings[idx].lastError = response.error ?? "Processing failed"
                    storageService.saveRecordings(recordings)
                }
                removeJob(job)
                isProcessing = false
                processNextIfNeeded()

            default:
                // Still processing — schedule re-poll with backoff
                var updatedJob = job
                updatedJob.retryCount += 1

                if updatedJob.retryCount >= UploadJob.maxPollRetries {
                    var recordings = storageService.loadRecordings()
                    if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                        recordings[idx].status = .failed
                        recordings[idx].lastError = "Timed out waiting for processing"
                        storageService.saveRecordings(recordings)
                    }
                    removeJob(job)
                    isProcessing = false
                    processNextIfNeeded()
                    return
                }

                let delay = updatedJob.pollRetryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                updateJob(updatedJob)

                isProcessing = false
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                processNextIfNeeded()
            }

        } catch {
            // Network/API error during poll — retry
            print("Poll failed: \(error)")
            var updatedJob = job
            updatedJob.retryCount += 1

            if updatedJob.retryCount >= UploadJob.maxPollRetries {
                var recordings = storageService.loadRecordings()
                if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                    recordings[idx].status = .failed
                    recordings[idx].lastError = error.localizedDescription
                    storageService.saveRecordings(recordings)
                }
                removeJob(job)
            } else {
                let delay = updatedJob.pollRetryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                updateJob(updatedJob)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            isProcessing = false
            processNextIfNeeded()
        }
    }

    // MARK: - Queue Persistence

    private func removeJob(_ job: UploadJob) {
        queue.removeAll { $0.id == job.id }
        saveQueue()
    }

    private func updateJob(_ job: UploadJob) {
        if let index = queue.firstIndex(where: { $0.id == job.id }) {
            queue[index] = job
            saveQueue()
        }
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFile.path),
              let data = try? Data(contentsOf: queueFile),
              let jobs = try? JSONDecoder().decode([UploadJob].self, from: data) else {
            return
        }
        queue = jobs
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}
