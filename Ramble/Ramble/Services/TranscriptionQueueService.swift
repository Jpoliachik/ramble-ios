//
//  TranscriptionQueueService.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class TranscriptionQueueService: ObservableObject {
    static let shared = TranscriptionQueueService()

    @Published private(set) var isProcessing = false

    var hasActiveWork: Bool {
        isProcessing || !queue.isEmpty
    }

    private let appleSpeech = AppleSpeechTranscriptionService()
    private let proxyService = ProxyTranscriptionService()
    private let storageService = StorageService.shared
    private let settingsService = SettingsService.shared
    private var queue: [TranscriptionJob] = []
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("transcription_queue.json")

    private init() {
        loadQueue()
    }

    // MARK: - Public API

    func enqueue(recordingId: UUID) {
        // Don't double-enqueue
        guard !queue.contains(where: { $0.recordingId == recordingId }) else { return }
        let settings = settingsService.load()
        let job = TranscriptionJob(recordingId: recordingId, provider: settings.transcriptionProvider)
        queue.append(job)
        saveQueue()
        processNextIfNeeded()
    }

    func processNextIfNeeded() {
        guard !isProcessing, let job = queue.first else { return }
        processJob(job)
    }

    func resumePendingJobs() {
        // Re-enqueue any recordings stuck in recorded/transcribing state
        let recordings = storageService.loadRecordings()
        for recording in recordings {
            if recording.status == .recorded || recording.status == .transcribing {
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

    // MARK: - Job Processing

    private func processJob(_ job: TranscriptionJob) {
        isProcessing = true

        Task {
            await processTranscription(job)
        }
    }

    private func processTranscription(_ job: TranscriptionJob) async {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) else {
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Update status to transcribing
        recordings[idx].status = .transcribing
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
            let text: String
            if job.provider.isCloud {
                text = try await proxyService.transcribe(audioURL: audioURL)
            } else {
                text = try await appleSpeech.transcribe(audioURL: audioURL)
            }

            // Success — update recording
            var updatedRecordings = storageService.loadRecordings()
            if let i = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[i].status = .completed
                updatedRecordings[i].transcription = text
                updatedRecordings[i].lastError = nil
                storageService.saveRecordings(updatedRecordings)
            }

            removeJob(job)
            isProcessing = false

            // Enqueue webhook if enabled and configured
            let settings = settingsService.load()
            if settings.webhookEnabled, let webhookURL = settings.webhookURL, !webhookURL.isEmpty {
                WebhookQueueService.shared.enqueue(recordingId: job.recordingId)
            }

            processNextIfNeeded()

        } catch {
            await handleTranscriptionFailure(job: job, error: error.localizedDescription)
        }
    }

    private func handleTranscriptionFailure(job: TranscriptionJob, error: String) async {
        print("Transcription failed: \(error)")

        var updatedJob = job
        updatedJob.retryCount += 1

        var recordings = storageService.loadRecordings()
        if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
            recordings[idx].lastError = error
            if updatedJob.retryCount >= TranscriptionJob.maxRetries {
                recordings[idx].status = .failed
                storageService.saveRecordings(recordings)
                removeJob(job)
            } else {
                recordings[idx].status = .recorded
                let delay = updatedJob.retryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                storageService.saveRecordings(recordings)
                updateJob(updatedJob)
                print("Transcription retry \(updatedJob.retryCount)/\(TranscriptionJob.maxRetries) in \(Int(delay))s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        isProcessing = false
        processNextIfNeeded()
    }

    // MARK: - Queue Persistence

    private func removeJob(_ job: TranscriptionJob) {
        queue.removeAll { $0.id == job.id }
        saveQueue()
    }

    private func updateJob(_ job: TranscriptionJob) {
        if let index = queue.firstIndex(where: { $0.id == job.id }) {
            queue[index] = job
            saveQueue()
        }
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFile.path),
              let data = try? Data(contentsOf: queueFile),
              let jobs = try? JSONDecoder().decode([TranscriptionJob].self, from: data) else {
            return
        }
        queue = jobs
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}
