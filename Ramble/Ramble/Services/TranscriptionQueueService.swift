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

                let transcription = try await transcriptionService.transcribe(audioURL: audioURL)

                var updatedRecordings = storageService.loadRecordings()
                if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                    updatedRecordings[idx].transcription = transcription
                    updatedRecordings[idx].transcriptionStatus = .completed
                    storageService.saveRecordings(updatedRecordings)

                    // Send to webhook
                    await webhookService.sendRecording(updatedRecordings[idx])
                }

                removeJob(job)
                isProcessing = false
                processNextIfNeeded()

            } catch {
                print("Transcription failed: \(error)")

                var updatedJob = job
                updatedJob.retryCount += 1

                var updatedRecordings = storageService.loadRecordings()
                if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
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
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
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
