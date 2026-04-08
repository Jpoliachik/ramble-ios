//
//  WebhookQueueService.swift
//  Ramble
//

import Combine
import CommonCrypto
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
                recordings[idx].activityLog.append(ActivityEntry("Webhook skipped — no valid URL configured"))
                storageService.saveRecordings(recordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Validate URL before sending
        if let validationError = Self.validateWebhookURL(webhookURLString) {
            var recordings = storageService.loadRecordings()
            if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                recordings[idx].webhookStatus = .failed
                recordings[idx].activityLog.append(ActivityEntry("Webhook rejected — \(validationError)"))
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

            // Compute HMAC-SHA256 signature of the payload body
            let signature = Self.hmacSHA256(data: jsonData, key: settings.webhookSecret)

            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("sha256=\(signature)", forHTTPHeaderField: "X-Webhook-Signature")
            request.httpBody = jsonData
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await handleWebhookFailure(job: job, error: "Invalid response", httpStatus: nil)
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                var updatedRecordings = storageService.loadRecordings()
                if let i = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                    updatedRecordings[i].webhookStatus = .delivered
                    updatedRecordings[i].activityLog.append(
                        ActivityEntry("Webhook delivered", httpStatus: httpResponse.statusCode)
                    )
                    storageService.saveRecordings(updatedRecordings)
                }
                removeJob(job)
                isProcessing = false
                processNextIfNeeded()
            } else {
                await handleWebhookFailure(
                    job: job,
                    error: "HTTP \(httpResponse.statusCode)",
                    httpStatus: httpResponse.statusCode
                )
            }
        } catch {
            await handleWebhookFailure(job: job, error: Self.sanitizedError(error), httpStatus: nil)
        }
    }

    // MARK: - URL Validation

    /// Validates a webhook URL. Returns nil if valid, or a user-facing error string if invalid.
    static func validateWebhookURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return "Invalid URL format"
        }

        // Require HTTPS
        guard url.scheme?.lowercased() == "https" else {
            return "URL must use HTTPS"
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return "URL must include a hostname"
        }

        // Reject localhost and loopback
        let blockedHosts = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
        if blockedHosts.contains(host) {
            return "URL cannot point to localhost"
        }

        // Reject private/internal IP ranges
        if isPrivateIP(host) {
            return "URL cannot point to a private network address"
        }

        // Reject cloud metadata endpoints
        if host == "169.254.169.254" || host.hasSuffix(".internal") {
            return "URL cannot point to internal services"
        }

        return nil
    }

    private static func isPrivateIP(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }

        // 10.0.0.0/8
        if parts[0] == 10 { return true }
        // 172.16.0.0/12
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        // 192.168.0.0/16
        if parts[0] == 192, parts[1] == 168 { return true }
        // 169.254.0.0/16 (link-local)
        if parts[0] == 169, parts[1] == 254 { return true }

        return false
    }

    // MARK: - HMAC Signing

    static func hmacSHA256(data: Data, key: String) -> String {
        let keyData = Data(key.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBytes.baseAddress, keyData.count,
                    dataBytes.baseAddress, data.count,
                    &digest
                )
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Error Sanitization

    private static func sanitizedError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorTimedOut: return "Request timed out"
            case NSURLErrorNotConnectedToInternet: return "No internet connection"
            case NSURLErrorCannotFindHost: return "Cannot find host"
            case NSURLErrorCannotConnectToHost: return "Cannot connect to host"
            case NSURLErrorSecureConnectionFailed: return "TLS connection failed"
            case NSURLErrorServerCertificateUntrusted: return "Untrusted certificate"
            default: return "Network error (code \(nsError.code))"
            }
        default:
            return "Request failed"
        }
    }

    // MARK: - Test Webhook

    /// Sends a test webhook payload. Returns nil on success or an error string on failure.
    func sendTestWebhook() async -> String? {
        let settings = settingsService.load()

        guard let webhookURLString = settings.webhookURL,
              !webhookURLString.isEmpty else {
            return "No webhook URL configured"
        }

        if let validationError = Self.validateWebhookURL(webhookURLString) {
            return validationError
        }

        guard let webhookURL = URL(string: webhookURLString) else {
            return "Invalid URL"
        }

        let payload: [String: Any] = [
            "recording_id": "test-\(UUID().uuidString)",
            "created_at": Self.isoFormatter.string(from: Date()),
            "duration": 0.0,
            "transcription": "This is a test webhook from Ramble.",
            "device_id": settings.deviceId,
            "test": true
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let signature = Self.hmacSHA256(data: jsonData, key: settings.webhookSecret)

            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("sha256=\(signature)", forHTTPHeaderField: "X-Webhook-Signature")
            request.httpBody = jsonData
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return "Invalid response"
            }

            if (200...299).contains(httpResponse.statusCode) {
                return nil // success
            } else {
                return "HTTP \(httpResponse.statusCode)"
            }
        } catch {
            return Self.sanitizedError(error)
        }
    }

    private func handleWebhookFailure(job: WebhookJob, error: String, httpStatus: Int?) async {
        var updatedJob = job
        updatedJob.retryCount += 1

        let attempt = updatedJob.retryCount
        let maxAttempts = WebhookJob.maxRetries

        if attempt >= maxAttempts {
            var recordings = storageService.loadRecordings()
            if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                recordings[idx].webhookStatus = .failed
                recordings[idx].activityLog.append(
                    ActivityEntry("Webhook failed after \(maxAttempts) attempts — \(error)", httpStatus: httpStatus)
                )
                storageService.saveRecordings(recordings)
            }
            removeJob(job)
        } else {
            var recordings = storageService.loadRecordings()
            if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
                recordings[idx].webhookStatus = .pending
                let delay = updatedJob.retryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                recordings[idx].activityLog.append(
                    ActivityEntry("Webhook attempt \(attempt)/\(maxAttempts) failed — \(error), retrying in \(Int(delay))s", httpStatus: httpStatus)
                )
                storageService.saveRecordings(recordings)
            }
            let delay = updatedJob.retryDelaySeconds
            updateJob(updatedJob)
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
