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

    /// True when any transcription or webhook work is actively running
    var hasActiveWork: Bool {
        isProcessing || !activeWebhookRetryTasks.isEmpty
    }

    private let transcriptionService = TranscriptionService.shared
    private let storageService = StorageService.shared
    private let webhookService = WebhookService.shared
    private let settingsService = SettingsService.shared
    private var queue: [TranscriptionJob] = []
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("transcription_queue.json")
    private var activeWebhookRetryTasks: Set<UUID> = []

    private init() {
        loadQueue()
    }

    // MARK: - Transcription Queue

    func enqueue(recordingId: UUID) {
        let job = TranscriptionJob(recordingId: recordingId)
        queue.append(job)
        saveQueue()
        processNextIfNeeded()
    }

    func processNextIfNeeded() {
        guard !isProcessing, let job = queue.first else { return }
        processJob(job)
    }

    func resumePendingJobs() {
        processNextIfNeeded()
        processWebhookRetries()
    }

    /// Manually retry a failed transcription by re-enqueuing it
    func retryTranscription(for recordingId: UUID) {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        recordings[idx].transcriptionStatus = .pending
        recordings[idx].lastTranscriptionError = nil
        storageService.saveRecordings(recordings)

        enqueue(recordingId: recordingId)
    }

    // MARK: - Webhook Retry

    /// Manually retry webhook — resets retry counter and fires immediately
    func retryWebhook(for recordingId: UUID) async {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        // Reset automatic retry state
        recordings[idx].webhookRetryCount = 0
        recordings[idx].nextWebhookRetryAt = nil
        storageService.saveRecordings(recordings)

        await sendWebhookWithRetry(recordingId: recordingId)
    }

    /// Check all recordings for pending webhook retries and process them
    func processWebhookRetries() {
        let recordings = storageService.loadRecordings()
        for recording in recordings where recording.needsWebhookRetry {
            guard !activeWebhookRetryTasks.contains(recording.id) else { continue }
            scheduleWebhookRetry(for: recording.id, delay: 0)
        }
    }

    /// Schedule a webhook retry after a delay (runs independently from transcription queue)
    private func scheduleWebhookRetry(for recordingId: UUID, delay: TimeInterval) {
        guard !activeWebhookRetryTasks.contains(recordingId) else { return }
        activeWebhookRetryTasks.insert(recordingId)

        Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await sendWebhookWithRetry(recordingId: recordingId)
            activeWebhookRetryTasks.remove(recordingId)
        }
    }

    /// Send webhook and handle retry logic
    private func sendWebhookWithRetry(recordingId: UUID) async {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        let recording = recordings[idx]
        guard let attempt = await webhookService.sendRecording(recording) else { return }

        // Re-load to avoid stale data
        recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        recordings[idx].webhookAttempts.append(attempt)

        if attempt.success {
            recordings[idx].webhookRetryCount = 0
            recordings[idx].nextWebhookRetryAt = nil
            storageService.saveRecordings(recordings)
            return
        }

        // Webhook failed — schedule retry if under the limit
        recordings[idx].webhookRetryCount += 1
        let retryCount = recordings[idx].webhookRetryCount

        if retryCount < Recording.maxTotalWebhookRetries {
            let delay = recordings[idx].webhookRetryDelaySeconds
            let retryAt = Date().addingTimeInterval(delay)
            recordings[idx].nextWebhookRetryAt = retryAt

            let phase = retryCount <= Recording.maxInAppWebhookRetries ? "in-app" : "background"
            print("Webhook retry \(retryCount)/\(Recording.maxTotalWebhookRetries) (\(phase)) in \(Int(delay))s for recording \(recordingId)")

            storageService.saveRecordings(recordings)

            // Only schedule in-app retries automatically; background retries handled by BGTask
            if retryCount <= Recording.maxInAppWebhookRetries {
                scheduleWebhookRetry(for: recordingId, delay: delay)
            }
        } else {
            recordings[idx].nextWebhookRetryAt = nil
            print("All webhook retries exhausted for recording \(recordingId)")
            storageService.saveRecordings(recordings)
        }
    }

    // MARK: - Transcription Processing

    private func processJob(_ job: TranscriptionJob) {
        isProcessing = true

        var recordings = storageService.loadRecordings()
        guard let index = recordings.firstIndex(where: { $0.id == job.recordingId }) else {
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        recordings[index].transcriptionStatus = .uploading
        storageService.saveRecordings(recordings)

        let audioURL = recordings[index].audioFileURL

        Task {
            do {
                recordings[index].transcriptionStatus = .processing
                storageService.saveRecordings(recordings)

                let result = try await transcriptionService.transcribe(audioURL: audioURL)

                var updatedRecordings = storageService.loadRecordings()
                if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                    updatedRecordings[idx].transcription = result.text
                    updatedRecordings[idx].transcriptionStatus = .completed
                    updatedRecordings[idx].lastTranscriptionError = nil
                    updatedRecordings[idx].noSpeechProbability = result.noSpeechProbability
                    updatedRecordings[idx].transcriptionLanguage = result.language
                    storageService.saveRecordings(updatedRecordings)

                    // Send webhook (with automatic retry on failure)
                    let settings = settingsService.load()
                    let recording = updatedRecordings[idx]
                    if recording.isQualityAcceptable(threshold: settings.transcriptionQualityThreshold) {
                        await sendWebhookWithRetry(recordingId: job.recordingId)
                    } else {
                        print("Skipping webhook for low-quality transcription (no_speech_prob: \(result.noSpeechProbability ?? 0))")
                    }
                }

                removeJob(job)
                isProcessing = false
                processNextIfNeeded()

            } catch {
                let errorMessage = String(describing: error)
                print("Transcription failed: \(errorMessage)")

                var updatedJob = job
                updatedJob.retryCount += 1

                var updatedRecordings = storageService.loadRecordings()
                if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                    updatedRecordings[idx].lastTranscriptionError = errorMessage
                    if updatedJob.retryCount >= TranscriptionJob.maxRetries {
                        updatedRecordings[idx].transcriptionStatus = .failed
                        removeJob(job)
                    } else {
                        updatedRecordings[idx].transcriptionStatus = .pending
                        let delay = updatedJob.retryDelaySeconds
                        updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                        updateJob(updatedJob)
                    }
                    storageService.saveRecordings(updatedRecordings)
                }

                isProcessing = false

                if updatedJob.retryCount < TranscriptionJob.maxRetries {
                    let delay = updatedJob.retryDelayNanoseconds
                    print("Transcription retry \(updatedJob.retryCount)/\(TranscriptionJob.maxRetries) in \(Int(updatedJob.retryDelaySeconds))s")
                    try? await Task.sleep(nanoseconds: delay)
                    processNextIfNeeded()
                } else {
                    processNextIfNeeded()
                }
            }
        }
    }

    // MARK: - Queue access for UI

    func transcriptionJob(for recordingId: UUID) -> TranscriptionJob? {
        queue.first { $0.recordingId == recordingId }
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
