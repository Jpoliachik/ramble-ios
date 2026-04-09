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

    private let speechAnalyzer = SpeechAnalyzerTranscriptionService()
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
        let cloudModel: CloudModel? = settings.transcriptionProvider.isCloud ? settings.cloudModel : nil
        let job = TranscriptionJob(
            recordingId: recordingId,
            provider: settings.transcriptionProvider,
            cloudModel: cloudModel
        )
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

    /// Download the speech model and retry all recordings that failed due to missing model.
    func downloadModelAndRetryPending() async throws {
        log(message: "Speech model download started")
        do {
            try await speechAnalyzer.downloadModel()
            log(message: "Speech model downloaded")
        } catch {
            log(message: "Speech model download failed — \(error.localizedDescription)")
            throw error
        }

        let recordings = storageService.loadRecordings()
        for recording in recordings where recording.isModelNotInstalled {
            retry(recordingId: recording.id)
        }
    }

    /// Proactively prepare the speech model on app launch.
    func prepareModelIfNeeded() async {
        await speechAnalyzer.prepareModelIfNeeded()
    }

    /// Manually retry a failed recording by re-enqueuing it.
    /// Returns false if the cloud transcription limit has been reached.
    @discardableResult
    func retry(recordingId: UUID) -> Bool {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return false }

        let settings = settingsService.load()
        if settings.transcriptionProvider.isCloud
            && recordings[idx].cloudTranscriptionCount >= TranscriptionJob.maxCloudTranscriptions {
            return false
        }

        recordings[idx].status = .recorded
        recordings[idx].lastError = nil
        recordings[idx].activityLog.append(ActivityEntry("Manual retry requested"))
        storageService.saveRecordings(recordings)

        // Remove any existing job for this recording before re-enqueuing
        queue.removeAll { $0.recordingId == recordingId }
        saveQueue()

        enqueue(recordingId: recordingId)
        return true
    }

    // MARK: - Job Processing

    private func processJob(_ job: TranscriptionJob) {
        isProcessing = true

        Task {
            await processTranscription(job)
        }
    }

    private func providerLabel(for job: TranscriptionJob) -> String {
        if let model = job.cloudModel {
            return model.displayName
        }
        return job.provider.displayName
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

        // Block if this recording has exhausted its cloud transcription limit
        if job.provider.isCloud
            && recordings[idx].cloudTranscriptionCount >= TranscriptionJob.maxCloudTranscriptions {
            recordings[idx].status = .failed
            recordings[idx].lastError = "Cloud transcription limit reached (\(TranscriptionJob.maxCloudTranscriptions))"
            recordings[idx].activityLog.append(
                ActivityEntry("Blocked — \(providerLabel(for: job)) cloud transcription limit reached (\(TranscriptionJob.maxCloudTranscriptions) uses)")
            )
            storageService.saveRecordings(recordings)
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        do {
            let text: String
            if job.provider.isCloud {
                // Fetch fresh JWS at call time (not enqueue time) — tokens expire
                let jws = SubscriptionService.shared.currentJWSTransaction
                let request = ProxyTranscriptionRequest(
                    audioURL: audioURL,
                    model: job.cloudModel ?? .whisperLargeV3Turbo,
                    jwsTransaction: jws
                )
                text = try await proxyService.transcribe(request)
            } else {
                text = try await speechAnalyzer.transcribe(audioURL: audioURL)
            }

            // Success — update recording
            var updatedRecordings = storageService.loadRecordings()
            if let i = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[i].status = .completed
                updatedRecordings[i].transcription = text
                updatedRecordings[i].lastError = nil
                if job.provider.isCloud {
                    updatedRecordings[i].cloudTranscriptionCount += 1
                }
                updatedRecordings[i].activityLog.append(
                    ActivityEntry("Transcription completed via \(providerLabel(for: job))", httpStatus: job.provider.isCloud ? 200 : nil)
                )
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

        } catch TranscriptionError.subscriptionRequired {
            // Subscription missing or expired — fail immediately, don't retry
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.subscriptionRequired.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — premium subscription required", httpStatus: 403)
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch TranscriptionError.modelNotInstalled {
            // Model not downloaded — fail immediately, don't retry
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.modelNotInstalled.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — speech model not downloaded")
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch let transcriptionError as TranscriptionError {
            var httpStatus: Int?
            if case .proxyError(let code, _) = transcriptionError {
                httpStatus = code
            }
            await handleTranscriptionFailure(job: job, error: transcriptionError.localizedDescription, httpStatus: httpStatus)

        } catch {
            await handleTranscriptionFailure(job: job, error: error.localizedDescription)
        }
    }

    private func handleTranscriptionFailure(job: TranscriptionJob, error: String, httpStatus: Int? = nil) async {
        var updatedJob = job
        updatedJob.retryCount += 1

        var recordings = storageService.loadRecordings()
        if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
            recordings[idx].lastError = error
            if updatedJob.retryCount >= TranscriptionJob.maxRetries {
                recordings[idx].status = .failed
                recordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) after \(TranscriptionJob.maxRetries) attempts — \(error)", httpStatus: httpStatus)
                )
                storageService.saveRecordings(recordings)
                removeJob(job)
            } else {
                recordings[idx].status = .recorded
                let delay = updatedJob.retryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                recordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — \(error) (attempt \(updatedJob.retryCount)/\(TranscriptionJob.maxRetries), retry in \(Int(delay))s)", httpStatus: httpStatus)
                )
                storageService.saveRecordings(recordings)
                updateJob(updatedJob)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        isProcessing = false
        processNextIfNeeded()
    }

    // MARK: - Activity Log Helper

    /// Log an activity entry for model download events (not tied to a specific recording)
    private func log(message: String) {
        // Model download events apply to all model-not-installed recordings
        var recordings = storageService.loadRecordings()
        var changed = false
        for i in recordings.indices where recordings[i].isModelNotInstalled {
            recordings[i].activityLog.append(ActivityEntry(message))
            changed = true
        }
        if changed {
            storageService.saveRecordings(recordings)
        }
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
