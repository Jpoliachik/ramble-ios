//
//  Settings.swift
//  Ramble
//

import Foundation

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case appleSpeech = "apple_speech"
    case groqWhisper = "groq_whisper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .groqWhisper: return "Groq Whisper"
        }
    }

    var subtitle: String {
        switch self {
        case .appleSpeech:
            return "Free, private, on-device"
        case .groqWhisper:
            return "Fast, accurate, cloud-powered"
        }
    }

    var iconName: String {
        switch self {
        case .appleSpeech: return "iphone"
        case .groqWhisper: return "bolt.fill"
        }
    }

    var isCloud: Bool {
        switch self {
        case .appleSpeech: return false
        case .groqWhisper: return true
        }
    }

    /// The base URL for cloud transcription providers
    var baseURL: String? {
        switch self {
        case .appleSpeech: return nil
        case .groqWhisper: return "https://ramble-transcription-proxy.justinpoliachik.workers.dev"
        }
    }
}

struct Settings: Codable {
    var transcriptionProvider: TranscriptionProvider
    var webhookEnabled: Bool
    var webhookURL: String?
    var webhookSecret: String
    var deviceId: String

    init(
        transcriptionProvider: TranscriptionProvider = .appleSpeech,
        webhookEnabled: Bool = false,
        webhookURL: String? = nil,
        webhookSecret: String = Self.generateSecret(),
        deviceId: String = UUID().uuidString
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.webhookEnabled = webhookEnabled
        self.webhookURL = webhookURL
        self.webhookSecret = webhookSecret
        self.deviceId = deviceId
    }

    static func generateSecret() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    // Backward-compatible decoder: migrates from old keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        webhookURL = try container.decodeIfPresent(String.self, forKey: .webhookURL)

        webhookEnabled = try container.decodeIfPresent(Bool.self, forKey: .webhookEnabled)
            ?? (webhookURL != nil && !webhookURL!.isEmpty)

        webhookSecret = try container.decodeIfPresent(String.self, forKey: .webhookSecret)
            ?? Self.generateSecret()

        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
            ?? UUID().uuidString

        // Migrate provider: try new enum values first, then old values
        let oldProxyURL = try container.decodeIfPresent(String.self, forKey: .proxyBaseURL)
            ?? container.decodeIfPresent(String.self, forKey: .apiBaseURL)

        if let provider = try? container.decode(TranscriptionProvider.self, forKey: .transcriptionProvider) {
            transcriptionProvider = provider
        } else if let oldString = try? container.decode(String.self, forKey: .transcriptionProvider) {
            switch oldString {
            case "on_device": transcriptionProvider = .appleSpeech
            case "proxy": transcriptionProvider = .groqWhisper
            default: transcriptionProvider = .appleSpeech
            }
        } else if oldProxyURL != nil && !oldProxyURL!.isEmpty {
            transcriptionProvider = .groqWhisper
        } else {
            transcriptionProvider = .appleSpeech
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transcriptionProvider, forKey: .transcriptionProvider)
        try container.encode(webhookEnabled, forKey: .webhookEnabled)
        try container.encodeIfPresent(webhookURL, forKey: .webhookURL)
        try container.encode(webhookSecret, forKey: .webhookSecret)
        try container.encode(deviceId, forKey: .deviceId)
    }

    static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case transcriptionProvider
        case webhookEnabled
        case webhookURL
        case webhookSecret
        case deviceId
        // Legacy keys for migration
        case proxyBaseURL
        case apiBaseURL
        case apiToken
        case webhookAuthToken
    }
}
