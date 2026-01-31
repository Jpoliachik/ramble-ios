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

struct TranscriptionResult {
    let text: String
    let noSpeechProbability: Double?
    let language: String?
    let duration: Double?
}

final class TranscriptionService {
    static let shared = TranscriptionService()

    private init() {}

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
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

        // Response format field (verbose_json to get quality metrics)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("verbose_json\r\n")

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

        let result = try JSONDecoder().decode(VerboseTranscriptionResponse.self, from: data)

        // Calculate average no_speech_prob across all segments
        let noSpeechProb: Double?
        if !result.segments.isEmpty {
            let total = result.segments.reduce(0.0) { $0 + $1.no_speech_prob }
            noSpeechProb = total / Double(result.segments.count)
        } else {
            noSpeechProb = nil
        }

        return TranscriptionResult(
            text: result.text,
            noSpeechProbability: noSpeechProb,
            language: result.language,
            duration: result.duration
        )
    }
}

private struct VerboseTranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [TranscriptionSegment]
}

private struct TranscriptionSegment: Decodable {
    let no_speech_prob: Double
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
