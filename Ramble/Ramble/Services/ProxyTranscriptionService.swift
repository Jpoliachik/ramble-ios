//
//  ProxyTranscriptionService.swift
//  Ramble
//

import AVFoundation
import Foundation

struct ProxyTranscriptionRequest {
    let audioURL: URL
    let model: CloudModel
    let language: TranscriptionLanguage
    let customVocabulary: String
    let removeFillerWords: Bool
    let jwsTransaction: String?
}

final class ProxyTranscriptionService {
    private let settingsService = SettingsService.shared
    private let appAttestService = AppAttestService.shared

    func transcribe(_ request: ProxyTranscriptionRequest) async throws -> String {
        let settings = settingsService.load()

        guard let baseURLString = settings.transcriptionProvider.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw TranscriptionError.proxyNotConfigured
        }

        guard FileManager.default.fileExists(atPath: request.audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        // Best-effort attestation before the first request
        try? await appAttestService.attestIfNeeded()

        // Providers cap both the size and the length of a single request, and
        // at 16 kHz mono AAC the length limit is hit first by a wide margin —
        // 25 minutes of speech is only a few MB.
        let attributes = try FileManager.default.attributesOfItem(atPath: request.audioURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        let duration = await audioDuration(of: request.audioURL) ?? 0

        let isOversized = fileSize >= Constants.Transcription.maxSingleUploadSize
        let isTooLong = duration > Constants.Transcription.maxSingleUploadDuration

        if isOversized || isTooLong {
            return try await transcribeChunked(
                baseURL: baseURL, request: request, deviceId: settings.deviceId
            )
        }

        let audioData = try Data(contentsOf: request.audioURL)
        return try await uploadAndTranscribe(
            audioData: audioData, baseURL: baseURL, request: request,
            deviceId: settings.deviceId
        )
    }

    /// Duration in seconds, or nil when the asset can't be read — in which case
    /// the file-size check alone decides whether to chunk.
    private func audioDuration(of url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    // MARK: - Chunked Transcription

    private func transcribeChunked(
        baseURL: URL, request: ProxyTranscriptionRequest, deviceId: String
    ) async throws -> String {
        let chunkURLs = try await splitAudioIntoChunks(audioURL: request.audioURL)

        defer {
            for url in chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        var transcripts: [String] = []
        for chunkURL in chunkURLs {
            let audioData = try Data(contentsOf: chunkURL)
            let text = try await uploadAndTranscribe(
                audioData: audioData, baseURL: baseURL, request: request,
                deviceId: deviceId
            )
            if !text.isEmpty {
                transcripts.append(text)
            }
        }

        // Each chunk comes back already broken into paragraphs, so joining on a
        // space would run the tail of one chunk into the head of the next and
        // leave the seams as the only places in a long transcript without a
        // break. A chunk boundary is a pause in the recording — treat it like
        // any other paragraph break.
        return transcripts.joined(separator: "\n\n")
    }

    private func splitAudioIntoChunks(audioURL: URL) async throws -> [URL] {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        guard totalSeconds > 0 else {
            throw TranscriptionError.recognitionFailed("Audio file has no duration")
        }

        let chunkDuration = Constants.Transcription.chunkDurationSeconds
        var chunks: [URL] = []
        var startSeconds: Double = 0

        while startSeconds < totalSeconds {
            let endSeconds = min(startSeconds + chunkDuration, totalSeconds)
            let start = CMTime(seconds: startSeconds, preferredTimescale: 44100)
            let end = CMTime(seconds: endSeconds, preferredTimescale: 44100)
            let timeRange = CMTimeRange(start: start, end: end)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).m4a")

            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                for chunk in chunks { try? FileManager.default.removeItem(at: chunk) }
                throw TranscriptionError.recognitionFailed("Failed to create audio export session")
            }

            exportSession.outputURL = tempURL
            exportSession.outputFileType = .m4a
            exportSession.timeRange = timeRange

            await exportSession.export()

            guard exportSession.status == .completed else {
                for chunk in chunks { try? FileManager.default.removeItem(at: chunk) }
                try? FileManager.default.removeItem(at: tempURL)
                let errorMsg = exportSession.error?.localizedDescription ?? "Unknown error"
                throw TranscriptionError.recognitionFailed("Failed to split audio: \(errorMsg)")
            }

            chunks.append(tempURL)
            startSeconds = endSeconds
        }

        return chunks
    }

    // MARK: - Upload

    private func uploadAndTranscribe(
        audioData: Data, baseURL: URL, request: ProxyTranscriptionRequest,
        deviceId: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("transcribe")
        let boundary = UUID().uuidString

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        // Dev override key bypasses subscription check on the proxy (any build)
        let overrideKey = UserDefaults.standard.string(forKey: SubscriptionService.devOverrideUserDefaultsKey)
        if let overrideKey, !overrideKey.isEmpty {
            urlRequest.setValue("DevBypass \(overrideKey)", forHTTPHeaderField: "Authorization")
        } else if let jws = request.jwsTransaction {
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

        body.appendField(name: "model", value: request.model.rawValue, boundary: boundary)

        if let languageCode = request.language.code, request.model.supports(request.language) {
            body.appendField(name: "language", value: languageCode, boundary: boundary)
        }

        let vocab = request.customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty {
            body.appendField(name: "vocabulary", value: vocab, boundary: boundary)
        }

        if request.removeFillerWords {
            body.appendField(name: "remove_filler_words", value: "true", boundary: boundary)
        }

        body.appendString("--\(boundary)--\r\n")

        // App Attest assertion — ties this specific request body to a verified device
        if let attestResult = await appAttestService.generateAssertion(for: body) {
            urlRequest.setValue(attestResult.keyId, forHTTPHeaderField: "X-App-Attest-Key-Id")
            urlRequest.setValue(
                attestResult.assertion.base64EncodedString(),
                forHTTPHeaderField: "X-App-Attest"
            )
        }

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

        // 403 = subscription required OR attestation failed
        if httpResponse.statusCode == 403 {
            if let errorJson = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               errorJson.error.contains("attestation") {
                throw TranscriptionError.attestationFailed
            }
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

    mutating func appendField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString(value)
        appendString("\r\n")
    }
}
