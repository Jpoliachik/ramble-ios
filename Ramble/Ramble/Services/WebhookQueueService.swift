//
//  WebhookQueueService.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class WebhookQueueService: ObservableObject {
    static let shared = WebhookQueueService()

    @Published private(set) var isProcessing = false

    var hasActiveWork: Bool {
        isProcessing || !queue.isEmpty
    }

    private let storageService = StorageService.shared
    private let settingsService = SettingsService.shared
    private var queue: [WebhookJob] = []
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("webhook_queue.json")

    private init() {
        loadQueue()
    }

    // MARK: - Public API

    func enqueue(recordingId: UUID) {
        // Don't double-enqueue
        guard !queue.contains(where: { $0.recordingId == recordingId }) else { return }

        let settings = settingsService.load()
        guard settings.webhookEnabled,
              let webhookURL = settings.webhookURL,
              !webhookURL.isEmpty else { return }

        // Update recording webhook status
        var recordings = storageService.loadRecordings()
        if let idx = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[idx].webhookStatus = .pending
            storageService.saveRecordings(recordings)
        }

        let job = WebhookJob(recordingId: recordingId)
        queue.append(job)
        saveQueue()
        processNextIfNeeded()
    }

    func processNextIfNeeded() {
        guard !isProcessing, let job = queue.first else { return }
        processJob(job)
    }

    func resumePendingJobs() {
        // Re-enqueue any recordings with pending/sending webhook status
        let recordings = storageService.loadRecordings()
        for recording in recordings {
            if let ws = recording.webhookStatus, (ws == .pending || ws == .sending) {
                if !queue.contains(where: { $0.recordingId == recording.id }) {
                    let job = WebhookJob(recordingId: recording.id)
                    queue.append(job)
                }
            }
        }
        saveQueue()
        processNextIfNeeded()
    }

    // MARK: - Job Processing

    private func processJob(_ job: WebhookJob) {
        isProcessing = true

        Task {
            await processWebhook(job)
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private func processWebhook(_ job: WebhookJob) async {
        let settings = settingsService.load()

        guard let webhookURLString = settings.webhookURL,
              !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            // Webhook URL removed — mark as failed and move on
            var recordings = storageService.loadRecordings()
            if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                recordings[idx].webhookStatus = .failed
                storageService.saveRecordings(recordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) else {
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Update webhook status to sending
        recordings[idx].webhookStatus = .sending
        storageService.saveRecordings(recordings)

        let recording = recordings[idx]

        // Build webhook payload
        let payload: [String: Any] = [
            "recording_id": recording.id.uuidString,
            "created_at": Self.isoFormatter.string(from: recording.createdAt),
            "duration": recording.duration,
            "transcription": recording.transcription ?? "",
            "device_id": settings.deviceId
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(settings.webhookSecret, forHTTPHeaderField: "X-Webhook-Secret")
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await handleWebhookFailure(job: job, error: "Invalid response from webhook")
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                var updatedRecordings = storageService.loadRecordings()
                if let i = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                    updatedRecordings[i].webhookStatus = .delivered
                    storageService.saveRecordings(updatedRecordings)
                }
                removeJob(job)
                isProcessing = false
                processNextIfNeeded()
            } else {
                await handleWebhookFailure(job: job, error: "Webhook returned \(httpResponse.statusCode)")
            }
        } catch {
            await handleWebhookFailure(job: job, error: error.localizedDescription)
        }
    }

    private func handleWebhookFailure(job: WebhookJob, error: String) async {
        print("Webhook failed: \(error)")

        var updatedJob = job
        updatedJob.retryCount += 1

        if updatedJob.retryCount >= WebhookJob.maxRetries {
            var recordings = storageService.loadRecordings()
            if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                recordings[idx].webhookStatus = .failed
                storageService.saveRecordings(recordings)
            }
            removeJob(job)
        } else {
            var recordings = storageService.loadRecordings()
            if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                recordings[idx].webhookStatus = .pending
                storageService.saveRecordings(recordings)
            }
            let delay = updatedJob.retryDelaySeconds
            updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
            updateJob(updatedJob)
            print("Webhook retry \(updatedJob.retryCount)/\(WebhookJob.maxRetries) in \(Int(delay))s")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        isProcessing = false
        processNextIfNeeded()
    }

    // MARK: - Queue Persistence

    private func removeJob(_ job: WebhookJob) {
        queue.removeAll { $0.id == job.id }
        saveQueue()
    }

    private func updateJob(_ job: WebhookJob) {
        if let index = queue.firstIndex(where: { $0.id == job.id }) {
            queue[index] = job
            saveQueue()
        }
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFile.path),
              let data = try? Data(contentsOf: queueFile),
              let jobs = try? JSONDecoder().decode([WebhookJob].self, from: data) else {
            return
        }
        queue = jobs
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}
