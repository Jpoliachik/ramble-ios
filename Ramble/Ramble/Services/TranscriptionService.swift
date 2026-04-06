//
//  TranscriptionService.swift
//  Ramble
//

import Foundation
import Speech

enum TranscriptionError: Error, LocalizedError {
    case audioFileNotFound
    case recognitionUnavailable
    case recognitionDenied
    case recognitionFailed(String)
    case proxyNotConfigured
    case proxyError(statusCode: Int, message: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound:
            return "Audio file not found"
        case .recognitionUnavailable:
            return "Speech recognition is not available on this device"
        case .recognitionDenied:
            return "Speech recognition permission denied. Enable in Settings > Privacy > Speech Recognition"
        case .recognitionFailed(let message):
            return "Transcription failed: \(message)"
        case .proxyNotConfigured:
            return "Cloud transcription not configured — set proxy URL in Settings"
        case .proxyError(let code, let message):
            return "Transcription service error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Apple Speech (On-Device)

final class AppleSpeechTranscriptionService {
    private let recognizer = SFSpeechRecognizer()

    func transcribe(audioURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognitionUnavailable
        }

        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else { throw TranscriptionError.recognitionDenied }
        case .denied, .restricted:
            throw TranscriptionError.recognitionDenied
        case .authorized:
            break
        @unknown default:
            break
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let result = result, result.isFinal else { return }
                hasResumed = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
