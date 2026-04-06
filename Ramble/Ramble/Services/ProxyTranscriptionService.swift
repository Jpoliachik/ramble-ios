//
//  ProxyTranscriptionService.swift
//  Ramble
//

import Foundation

final class ProxyTranscriptionService {
    private let settingsService = SettingsService.shared

    func transcribe(audioURL: URL) async throws -> String {
        let settings = settingsService.load()

        guard let baseURLString = settings.transcriptionProvider.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw TranscriptionError.proxyNotConfigured
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        let audioData = try Data(contentsOf: audioURL)
        let url = baseURL.appendingPathComponent("transcribe")
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(settings.deviceId, forHTTPHeaderField: "X-Device-ID")
        // TODO: Add App Attest token header for request authentication before public launch.
        // Use DCAppAttestService to generate attestation, send as X-App-Attest header,
        // and verify server-side to prove requests come from a legitimate app install.

        // Build multipart body
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.proxyError(statusCode: 0, message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            // Try to parse JSON error
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
