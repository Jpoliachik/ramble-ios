//
//  TranscriptionService.swift
//  Ramble
//

import Foundation

enum TranscriptionError: Error {
    case invalidAPIKey
    case fileNotFound
    case uploadFailed(String)
    case invalidResponse
    case apiError(String)
}

final class TranscriptionService {
    static let shared = TranscriptionService()

    private init() {}

    func transcribe(audioURL: URL) async throws -> String {
        let apiKey = Secrets.groqAPIKey
        guard apiKey != "YOUR_GROQ_API_KEY_HERE" && !apiKey.isEmpty else {
            throw TranscriptionError.invalidAPIKey
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound
        }

        let audioData = try Data(contentsOf: audioURL)

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: Constants.groqAPIEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        // Model field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(Constants.groqModel)\r\n")

        // File field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        // End boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError("Status \(httpResponse.statusCode): \(errorMessage)")
        }

        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
