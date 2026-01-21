//
//  WebhookService.swift
//  Ramble
//

import Foundation

final class WebhookService {
    static let shared = WebhookService()

    private let settingsService = SettingsService.shared

    private init() {}

    func sendRecording(_ recording: Recording) async {
        let settings = settingsService.load()

        guard let webhookURLString = settings.webhookURL,
              !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            return
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

        guard let data = try? JSONEncoder().encode(payload) else { return }
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("Webhook response: \(httpResponse.statusCode)")
            }
        } catch {
            print("Webhook failed: \(error)")
        }
    }
}

private struct WebhookPayload: Encodable {
    let id: String
    let createdAt: String
    let duration: TimeInterval
    let transcription: String?
}
