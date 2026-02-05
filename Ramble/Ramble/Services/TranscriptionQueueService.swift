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

    private let transcriptionService = TranscriptionService.shared
    private let storageService = StorageService.shared
    private let webhookService = WebhookService.shared
    private let settingsService = SettingsService.shared
    private var queue: [TranscriptionJob] = []
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("transcription_queue.json")

    private init() {
        loadQueue()
    }

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
    }

    /// Manually retry a failed transcription by re-enqueuing it
    func retryTranscription(for recordingId: UUID) {
        // Reset the recording status and clear any previous error
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        recordings[idx].transcriptionStatus = .pending
        recordings[idx].lastTranscriptionError = nil
        storageService.saveRecordings(recordings)

        // Enqueue a fresh job (retryCount starts at 0)
        enqueue(recordingId: recordingId)
    }

    func retryWebhook(for recordingId: UUID) async {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }

        if let attempt = await webhookService.sendRecording(recordings[idx]) {
            recordings[idx].webhookAttempts.append(attempt)
            storageService.saveRecordings(recordings)
        }
    }

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

                    // Only send to webhook if quality is acceptable
                    let settings = settingsService.load()
                    let recording = updatedRecordings[idx]
                    if recording.isQualityAcceptable(threshold: settings.transcriptionQualityThreshold) {
                        if let attempt = await webhookService.sendRecording(recording) {
                            updatedRecordings[idx].webhookAttempts.append(attempt)
                        }
                    } else {
                        print("Skipping webhook for low-quality transcription (no_speech_prob: \(result.noSpeechProbability ?? 0))")
                    }

                    storageService.saveRecordings(updatedRecordings)
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
                        updateJob(updatedJob)
                    }
                    storageService.saveRecordings(updatedRecordings)
                }

                isProcessing = false

                if updatedJob.retryCount < TranscriptionJob.maxRetries {
                    let delay = updatedJob.retryDelayNanoseconds
                    print("Retrying in \(delay / 1_000_000_000) seconds (attempt \(updatedJob.retryCount + 1)/\(TranscriptionJob.maxRetries))")
                    try? await Task.sleep(nanoseconds: delay)
                    processNextIfNeeded()
                } else {
                    processNextIfNeeded()
                }
            }
        }
    }

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
