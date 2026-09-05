//
//  TranscriptionService.swift
//  Ramble
//

import AVFAudio
import Foundation
import Speech

enum TranscriptionError: Error, LocalizedError {
    case audioFileNotFound
    case modelNotInstalled
    case whisperModelNotDownloaded
    case noSpeechDetected
    case localeNotSupported
    case speechAnalyzerUnavailable
    case recognitionFailed(String)
    case proxyNotConfigured
    case subscriptionRequired
    case attestationFailed
    case proxyError(statusCode: Int, message: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound:
            return "Audio file not found"
        case .modelNotInstalled:
            return SpeechAnalyzerTranscriptionService.modelNotInstalledError
        case .whisperModelNotDownloaded:
            return "Whisper model not downloaded — download it in Settings and retry."
        case .noSpeechDetected:
            return "No speech detected"
        case .localeNotSupported:
            return "Speech recognition is not supported for your language"
        case .speechAnalyzerUnavailable:
            return "On-device transcription requires iOS 26 or later"
        case .recognitionFailed(let message):
            return "Transcription failed: \(message)"
        case .subscriptionRequired:
            return "Premium subscription required for cloud transcription"
        case .attestationFailed:
            return "Device verification failed — please try again"
        case .proxyNotConfigured:
            return "Cloud transcription not configured — set proxy URL in Settings"
        case .proxyError(let code, let message):
            return "Transcription service error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Legacy SFSpeechRecognizer (On-Device, iOS 18+)

final class LegacySpeechTranscriptionService {
    func transcribe(audioURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.localeNotSupported
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }

        let text = result.bestTranscription.formattedString
        guard !text.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }
        return text
    }
}

// MARK: - SpeechAnalyzer (On-Device, iOS 26+)

final class SpeechAnalyzerTranscriptionService {
    static let modelNotInstalledError = "Speech model not downloaded. Tap to download and retry."

    /// Pick the supported locale that best matches the user's.
    ///
    /// Never compare BCP-47 identifiers directly. A device set to English with a
    /// different region format (Settings → General → Language & Region) reports
    /// something like `en-US-u-rg-dezzzz`, which matches no entry in
    /// `supportedLocales` even though English is fully supported. So match on
    /// language and region components, and fall back to any locale sharing the
    /// language.
    @available(iOS 26.0, *)
    private func bestMatch(in candidates: [Locale]) -> Locale? {
        let current = Locale.current
        guard let language = current.language.languageCode?.identifier else { return nil }

        if let sameRegion = candidates.first(where: {
            $0.language.languageCode?.identifier == language
                && $0.region?.identifier == current.region?.identifier
        }) {
            return sameRegion
        }
        return candidates.first { $0.language.languageCode?.identifier == language }
    }

    /// The locale transcription should actually use, or nil if the user's language
    /// isn't supported at all.
    @available(iOS 26.0, *)
    private func resolvedLocale() async -> Locale? {
        bestMatch(in: await SpeechTranscriber.supportedLocales)
    }

    /// Check whether the speech model for the user's language is installed on-device.
    func isModelInstalled() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return bestMatch(in: await SpeechTranscriber.installedLocales) != nil
    }

    /// Check whether the user's language is supported at all.
    func isLocaleSupported() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return await resolvedLocale() != nil
    }

    /// Download the speech model for the user's language. No-op if already installed.
    func downloadModel() async throws {
        guard #available(iOS 26.0, *) else {
            throw TranscriptionError.speechAnalyzerUnavailable
        }
        guard let locale = await resolvedLocale() else {
            throw TranscriptionError.localeNotSupported
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
    }

    /// Proactively prepare the model on app launch — best-effort, silent failures.
    func prepareModelIfNeeded() async {
        async let localeSupported = isLocaleSupported()
        async let modelInstalled = isModelInstalled()
        guard await localeSupported else { return }
        guard !(await modelInstalled) else { return }
        do {
            try await downloadModel()
            print("Speech model downloaded successfully")
        } catch {
            print("Speech model preparation failed: \(error.localizedDescription)")
        }
    }

    /// Transcribe an audio file using SpeechAnalyzer.
    func transcribe(audioURL: URL) async throws -> String {
        guard #available(iOS 26.0, *) else {
            throw TranscriptionError.speechAnalyzerUnavailable
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        async let localeSupported = isLocaleSupported()
        async let modelInstalled = isModelInstalled()

        guard await localeSupported else {
            throw TranscriptionError.localeNotSupported
        }

        guard await modelInstalled else {
            throw TranscriptionError.modelNotInstalled
        }

        guard let locale = await resolvedLocale() else {
            throw TranscriptionError.localeNotSupported
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Start collecting results before feeding audio
        async let transcriptionFuture: String = {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: audioURL)

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let result = try await transcriptionFuture

        guard !result.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        return result
    }
}
