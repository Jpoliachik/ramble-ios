//
//  Settings.swift
//  Ramble
//

import Foundation

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case appleSpeech = "apple_speech"
    case cloudTranscription = "cloud_transcription"
    case customEndpoint = "custom_endpoint"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .cloudTranscription: return "Cloud Transcription"
        case .customEndpoint: return "Custom Endpoint"
        }
    }

    var subtitle: String {
        switch self {
        case .appleSpeech:
            return "Free, private, on-device"
        case .cloudTranscription:
            return "Premium cloud-powered models"
        case .customEndpoint:
            return "Your own transcription server"
        }
    }

    var iconName: String {
        switch self {
        case .appleSpeech: return "iphone"
        case .cloudTranscription: return "cloud.fill"
        case .customEndpoint: return "server.rack"
        }
    }

    var isCloud: Bool {
        switch self {
        case .appleSpeech: return false
        case .cloudTranscription, .customEndpoint: return true
        }
    }

    /// The base URL for cloud transcription providers (custom endpoint URL is stored in Settings)
    var baseURL: String? {
        switch self {
        case .appleSpeech, .customEndpoint: return nil
        case .cloudTranscription: return "https://ramble-transcription-proxy.jpoliachik.workers.dev"
        }
    }

    /// A short label describing the transcription source, suitable for activity logs and webhook payloads
    func sourceLabel(customURL: String? = nil, cloudModel: CloudModel? = nil) -> String {
        switch self {
        case .appleSpeech:
            return "Apple Speech (on-device)"
        case .cloudTranscription:
            if let model = cloudModel {
                return "Ramble Cloud (\(model.rawValue))"
            }
            return "Ramble Cloud"
        case .customEndpoint:
            if let url = customURL, let host = URL(string: url)?.host {
                return "Custom (\(host))"
            }
            return "Custom Endpoint"
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
        case "custom_endpoint":
            self = .customEndpoint
        default:
            self = .appleSpeech
        }
    }
}

enum CloudModel: String, Codable, CaseIterable, Identifiable {
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperLargeV3Turbo: return "Whisper Large v3 Turbo"
        case .whisperLargeV3: return "Whisper Large v3"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperLargeV3Turbo: return "Fast and accurate (recommended)"
        case .whisperLargeV3: return "Highest accuracy"
        }
    }
}

struct Settings: Codable {
    var transcriptionProvider: TranscriptionProvider
    var cloudModel: CloudModel
    var customEndpointURL: String?
    var customEndpointAuthHeader: String?
    var webhookEnabled: Bool
    var webhookURL: String?
    var webhookSecret: String
    var deviceId: String

    init(
        transcriptionProvider: TranscriptionProvider = .appleSpeech,
        cloudModel: CloudModel = .whisperLargeV3Turbo,
        customEndpointURL: String? = nil,
        customEndpointAuthHeader: String? = nil,
        webhookEnabled: Bool = false,
        webhookURL: String? = nil,
        webhookSecret: String = Self.generateSecret(),
        deviceId: String = UUID().uuidString
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.cloudModel = cloudModel
        self.customEndpointURL = customEndpointURL
        self.customEndpointAuthHeader = customEndpointAuthHeader
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

        cloudModel = try container.decodeIfPresent(CloudModel.self, forKey: .cloudModel)
            ?? .whisperLargeV3Turbo

        customEndpointURL = try container.decodeIfPresent(String.self, forKey: .customEndpointURL)
        customEndpointAuthHeader = try container.decodeIfPresent(String.self, forKey: .customEndpointAuthHeader)

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
        try container.encodeIfPresent(customEndpointURL, forKey: .customEndpointURL)
        try container.encodeIfPresent(customEndpointAuthHeader, forKey: .customEndpointAuthHeader)
        try container.encode(webhookEnabled, forKey: .webhookEnabled)
        try container.encodeIfPresent(webhookURL, forKey: .webhookURL)
        // webhookSecret and deviceId are stored in Keychain, not on disk
    }

    static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case transcriptionProvider
        case cloudModel
        case customEndpointURL
        case customEndpointAuthHeader
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
