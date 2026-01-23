//
//  WebhookService.swift
//  Ramble
//

import Foundation

final class WebhookService {
    static let shared = WebhookService()

    private let settingsService = SettingsService.shared

    private init() {}

    var isWebhookConfigured: Bool {
        let settings = settingsService.load()
        guard let url = settings.webhookURL, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    var currentWebhookURL: String? {
        let settings = settingsService.load()
        return settings.webhookURL
    }

    func sendRecording(_ recording: Recording) async -> WebhookAttempt? {
        let settings = settingsService.load()

        guard let webhookURLString = settings.webhookURL,
              !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            return nil
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.webhookAuthToken)", forHTTPHeaderField: "Authorization")

        let payload = WebhookPayload(
            id: recording.id.uuidString,
            createdAt: ISO8601DateFormatter().string(from: recording.createdAt),
            duration: recording.duration,
            transcription: recording.transcription
        )

        guard let data = try? JSONEncoder().encode(payload) else {
            return WebhookAttempt(
                url: webhookURLString,
                success: false,
                errorMessage: "Failed to encode payload"
            )
        }
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let success = (200...299).contains(httpResponse.statusCode)
                return WebhookAttempt(
                    url: webhookURLString,
                    success: success,
                    statusCode: httpResponse.statusCode
                )
            }
            return WebhookAttempt(url: webhookURLString, success: false, errorMessage: "No response")
        } catch {
            return WebhookAttempt(
                url: webhookURLString,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }
}

private struct WebhookPayload: Encodable {
    let id: String
    let createdAt: String
    let duration: TimeInterval
    let transcription: String?
}
