//
//  Settings.swift
//  Ramble
//

import Foundation
import SwiftUI

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case appleSpeech = "apple_speech"
    case cloudTranscription = "cloud_transcription"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .cloudTranscription: return "Cloud Transcription"
        }
    }

    var subtitle: String {
        switch self {
        case .appleSpeech:
            if #available(iOS 26.0, *) {
                return "Free, private, on-device"
            } else {
                return "Free, on-device — update to iOS 26 for better accuracy"
            }
        case .cloudTranscription:
            return "Premium cloud-powered models"
        }
    }

    var iconName: String {
        switch self {
        case .appleSpeech: return "iphone"
        case .cloudTranscription: return "cloud.fill"
        }
    }

    var isCloud: Bool {
        switch self {
        case .appleSpeech: return false
        case .cloudTranscription: return true
        }
    }

    /// The base URL for cloud transcription providers
    var baseURL: String? {
        switch self {
        case .appleSpeech: return nil
        case .cloudTranscription: return "https://ramble-transcription-proxy.jpoliachik.workers.dev"
        }
    }

    /// Backward-compatible decoding: old raw values map to new cases
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "apple_speech", "on_device":
            self = .appleSpeech
        case "cloud_transcription", "groq_whisper", "proxy":
            self = .cloudTranscription
        default:
            self = .appleSpeech
        }
    }
}

enum CloudModel: String, Codable, CaseIterable, Identifiable {
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"
    case deepgramNova3 = "deepgram-nova-3"
    case openAIGPT4oTranscribe = "openai-gpt-4o-transcribe"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperLargeV3Turbo: return "Groq Whisper v3 Turbo"
        case .whisperLargeV3: return "Groq Whisper Large v3"
        case .deepgramNova3: return "Deepgram Nova-3"
        case .openAIGPT4oTranscribe: return "GPT-4o Transcribe"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperLargeV3Turbo: return "Fast and accurate — best all-around"
        case .whisperLargeV3: return "Best for accents and multilingual audio"
        case .deepgramNova3: return "Strong English accuracy, smart formatting"
        case .openAIGPT4oTranscribe: return "Highest accuracy in noisy environments"
        }
    }

    var iconName: String {
        switch self {
        case .whisperLargeV3Turbo, .whisperLargeV3: return "logo-groq"
        case .deepgramNova3: return "logo-deepgram"
        case .openAIGPT4oTranscribe: return "logo-openai"
        }
    }
}

struct Settings: Codable {
    var transcriptionProvider: TranscriptionProvider
    var cloudModel: CloudModel
    var webhookURL: String?
    var webhookSecret: String
    var deviceId: String
    var appearanceMode: AppearanceMode

    /// Whether webhook delivery is configured. Any non-empty URL means "send it."
    var isWebhookConfigured: Bool {
        guard let url = webhookURL else { return false }
        return !url.isEmpty
    }

    init(
        transcriptionProvider: TranscriptionProvider = .appleSpeech,
        cloudModel: CloudModel = .whisperLargeV3Turbo,
        webhookURL: String? = nil,
        webhookSecret: String = Self.generateSecret(),
        deviceId: String = UUID().uuidString,
        appearanceMode: AppearanceMode = .system
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.cloudModel = cloudModel
        self.webhookURL = webhookURL
        self.webhookSecret = webhookSecret
        self.deviceId = deviceId
        self.appearanceMode = appearanceMode
    }

    static func generateSecret() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    // Backward-compatible decoder: migrates from old keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        webhookURL = try container.decodeIfPresent(String.self, forKey: .webhookURL)

        webhookSecret = try container.decodeIfPresent(String.self, forKey: .webhookSecret)
            ?? Self.generateSecret()

        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
            ?? UUID().uuidString

        cloudModel = try container.decodeIfPresent(CloudModel.self, forKey: .cloudModel)
            ?? .whisperLargeV3Turbo

        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)
            ?? .system

        // Migrate provider: TranscriptionProvider.init(from:) handles old raw values
        let oldProxyURL = try container.decodeIfPresent(String.self, forKey: .proxyBaseURL)
            ?? container.decodeIfPresent(String.self, forKey: .apiBaseURL)

        if let provider = try? container.decode(TranscriptionProvider.self, forKey: .transcriptionProvider) {
            transcriptionProvider = provider
        } else if oldProxyURL != nil && !oldProxyURL!.isEmpty {
            transcriptionProvider = .cloudTranscription
        } else {
            transcriptionProvider = .appleSpeech
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transcriptionProvider, forKey: .transcriptionProvider)
        try container.encode(cloudModel, forKey: .cloudModel)
        try container.encodeIfPresent(webhookURL, forKey: .webhookURL)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        // webhookSecret and deviceId are stored in Keychain, not on disk
    }

    static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case transcriptionProvider
        case cloudModel
        case webhookURL
        case webhookSecret
        case deviceId
        case appearanceMode
        // Legacy keys for migration
        case webhookEnabled
        case proxyBaseURL
        case apiBaseURL
        case apiToken
        case webhookAuthToken
    }
}
