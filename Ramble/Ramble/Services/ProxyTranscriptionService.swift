//
//  ProxyTranscriptionService.swift
//  Ramble
//

import Foundation

struct ProxyTranscriptionRequest {
    let audioURL: URL
    let model: CloudModel
    let jwsTransaction: String?
}

final class ProxyTranscriptionService {
    private let settingsService = SettingsService.shared

    func transcribe(_ request: ProxyTranscriptionRequest) async throws -> String {
        let settings = settingsService.load()

        guard let baseURLString = settings.transcriptionProvider.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw TranscriptionError.proxyNotConfigured
        }

        guard FileManager.default.fileExists(atPath: request.audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        let audioData = try Data(contentsOf: request.audioURL)
        let url = baseURL.appendingPathComponent("transcribe")
        let boundary = UUID().uuidString

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(settings.deviceId, forHTTPHeaderField: "X-Device-ID")

        // Subscription JWS for server-side verification
        if let jws = request.jwsTransaction {
            urlRequest.setValue("Bearer \(jws)", forHTTPHeaderField: "Authorization")
        }

        // Build multipart body
        var body = Data()

        // Audio file part
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")

        // Model selection part
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString(request.model.rawValue)
        body.appendString("\r\n")

        body.appendString("--\(boundary)--\r\n")

        urlRequest.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw TranscriptionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.proxyError(statusCode: 0, message: "Invalid response")
        }

        // 403 = subscription required or expired
        if httpResponse.statusCode == 403 {
            throw TranscriptionError.subscriptionRequired
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if let json = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw TranscriptionError.proxyError(
                    statusCode: httpResponse.statusCode,
                    message: json.error
                )
            }
            throw TranscriptionError.proxyError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        let result = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        return result.text
    }
}

// MARK: - Response Types

private struct TranscribeResponse: Decodable {
    let text: String
}

private struct ErrorResponse: Decodable {
    let error: String
}

// MARK: - Data Extension

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
