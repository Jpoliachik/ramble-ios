//
//  ProxyTranscriptionService.swift
//  Ramble
//

import AVFoundation
import Foundation

struct ProxyTranscriptionRequest {
    let audioURL: URL
    let model: CloudModel
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

        // Check file size to determine if chunking is needed
        let attributes = try FileManager.default.attributesOfItem(atPath: request.audioURL.path)
        let fileSize = attributes[.size] as? Int ?? 0

        if fileSize < Constants.Transcription.maxSingleUploadSize {
            let audioData = try Data(contentsOf: request.audioURL)
            return try await uploadAndTranscribe(
                audioData: audioData, baseURL: baseURL, request: request,
                deviceId: settings.deviceId
            )
        } else {
            return try await transcribeChunked(
                baseURL: baseURL, request: request, deviceId: settings.deviceId
            )
        }
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

        return transcripts.joined(separator: " ")
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

        // Dev bypass token skips JWS verification (debug builds only, gitignored secret)
        #if DEBUG
        if let bypassToken = Secrets.devBypassToken {
            urlRequest.setValue("DevBypass \(bypassToken)", forHTTPHeaderField: "Authorization")
        } else if let jws = request.jwsTransaction {
            urlRequest.setValue("Bearer \(jws)", forHTTPHeaderField: "Authorization")
        }
        #else
        if let jws = request.jwsTransaction {
            urlRequest.setValue("Bearer \(jws)", forHTTPHeaderField: "Authorization")
        }
        #endif

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
}
