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
    case localWhisper = "local_whisper"
    case cloudTranscription = "cloud_transcription"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .localWhisper: return "Whisper v3 Turbo"
        case .cloudTranscription: return "Cloud Transcription"
        }
    }

    var subtitle: String {
        switch self {
        case .appleSpeech:
            if #available(iOS 26.0, *) {
                return "Built into iOS · works offline"
            } else {
                return "Free, on-device"
            }
        case .localWhisper:
            return "On-device · \(LocalWhisperTranscriptionService.modelDownloadSizeLabel) download"
        case .cloudTranscription:
            return "Premium cloud-powered models"
        }
    }

    var iconName: String {
        switch self {
        case .appleSpeech: return "iphone"
        case .localWhisper: return "waveform"
        case .cloudTranscription: return "cloud.fill"
        }
    }

    var isCloud: Bool {
        switch self {
        case .appleSpeech, .localWhisper: return false
        case .cloudTranscription: return true
        }
    }

    /// The base URL for cloud transcription providers
    var baseURL: String? {
        switch self {
        case .appleSpeech, .localWhisper: return nil
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
        case "local_whisper":
            self = .localWhisper
        case "cloud_transcription", "groq_whisper", "proxy":
            self = .cloudTranscription
        default:
            self = .appleSpeech
        }
    }
}

/// Language hint sent to cloud transcription providers.
/// `.auto` lets each provider auto-detect (mapped to `multi` for Deepgram).
/// Other cases pass an ISO-639-1 code directly to all providers.
/// Picker UI shows all cases; rows are disabled when the selected `CloudModel`
/// doesn't support the language.
enum TranscriptionLanguage: String, Codable, CaseIterable, Identifiable {
    case auto
    case af, ar, bg, bn, ca, cs, cy, da, de, el, en, es, et, fa, fi, fr, he, hi, hr,
         hu, id, it, ja, ko, lt, lv, ms, nl, no, pl, pt, ro, ru, sk, sv, sw, ta, te,
         th, tl, tr, uk, ur, vi, zh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .af: return "Afrikaans"
        case .ar: return "Arabic"
        case .bg: return "Bulgarian"
        case .bn: return "Bengali"
        case .ca: return "Catalan"
        case .cs: return "Czech"
        case .cy: return "Welsh"
        case .da: return "Danish"
        case .de: return "German"
        case .el: return "Greek"
        case .en: return "English"
        case .es: return "Spanish"
        case .et: return "Estonian"
        case .fa: return "Persian"
        case .fi: return "Finnish"
        case .fr: return "French"
        case .he: return "Hebrew"
        case .hi: return "Hindi"
        case .hr: return "Croatian"
        case .hu: return "Hungarian"
        case .id: return "Indonesian"
        case .it: return "Italian"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .lt: return "Lithuanian"
        case .lv: return "Latvian"
        case .ms: return "Malay"
        case .nl: return "Dutch"
        case .no: return "Norwegian"
        case .pl: return "Polish"
        case .pt: return "Portuguese"
        case .ro: return "Romanian"
        case .ru: return "Russian"
        case .sk: return "Slovak"
        case .sv: return "Swedish"
        case .sw: return "Swahili"
        case .ta: return "Tamil"
        case .te: return "Telugu"
        case .th: return "Thai"
        case .tl: return "Tagalog"
        case .tr: return "Turkish"
        case .uk: return "Ukrainian"
        case .ur: return "Urdu"
        case .vi: return "Vietnamese"
        case .zh: return "Chinese"
        }
    }

    /// ISO-639-1 code to send to providers, or nil for auto-detect.
    var code: String? {
        self == .auto ? nil : rawValue
    }

    /// Alphabetized by display name, with `.auto` pinned first. Computed once.
    static let sortedCases: [TranscriptionLanguage] = {
        let rest = allCases.filter { $0 != .auto }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return [.auto] + rest
    }()
}

enum CloudModel: String, Codable, CaseIterable, Identifiable {
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"
    case deepgramNova3 = "deepgram-nova-3"
    case openAIGPTTranscribe = "openai-gpt-transcribe"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperLargeV3Turbo: return "Groq Whisper v3 Turbo"
        case .whisperLargeV3: return "Groq Whisper Large v3"
        case .deepgramNova3: return "Deepgram Nova-3"
        case .openAIGPTTranscribe: return "GPT-Transcribe"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperLargeV3Turbo: return "Fast & accurate default"
        case .whisperLargeV3: return "Accents & multilingual"
        case .deepgramNova3: return "Clean English formatting"
        case .openAIGPTTranscribe: return "Best for noisy audio"
        }
    }

    var iconName: String {
        switch self {
        case .whisperLargeV3Turbo, .whisperLargeV3: return "logo-groq"
        case .deepgramNova3: return "logo-deepgram"
        case .openAIGPTTranscribe: return "logo-openai"
        }
    }

    /// Backward-compatible decoding. Retired model IDs map to whatever replaced
    /// them, so a stored preference survives a model swap, and an unrecognized
    /// ID falls back to the default rather than failing the whole decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        // GPT-Transcribe replaced the gpt-4o-transcribe family.
        case "openai-gpt-4o-transcribe":
            self = .openAIGPTTranscribe
        default:
            self = CloudModel(rawValue: rawValue) ?? .whisperLargeV3Turbo
        }
    }

    /// Languages this model accepts as a hint (excluding `.auto`, which is
    /// always allowed). Used by the picker to show only relevant rows.
    /// Whisper and GPT-Transcribe both cover the full enum; Nova-3 has a
    /// fixed subset.
    var supportedLanguages: Set<TranscriptionLanguage> {
        switch self {
        case .whisperLargeV3Turbo, .whisperLargeV3, .openAIGPTTranscribe:
            return Self.broadLanguageSupport
        case .deepgramNova3:
            return Self.deepgramNova3Languages
        }
    }

    func supports(_ language: TranscriptionLanguage) -> Bool {
        language == .auto || supportedLanguages.contains(language)
    }

    /// Every language in the enum. Whisper supports ~99 languages, and
    /// GPT-Transcribe accepts ISO-639-1 codes across a comparable range
    /// (OpenAI doesn't publish a per-model list), so the enum is a subset of
    /// what both models take.
    /// Authoritative lists:
    ///   https://github.com/openai/whisper#available-models-and-languages
    ///   https://console.groq.com/docs/speech-to-text
    ///   https://developers.openai.com/api/docs/guides/transcription
    private static let broadLanguageSupport: Set<TranscriptionLanguage> =
        Set(TranscriptionLanguage.allCases.filter { $0 != .auto })

    /// Deepgram Nova-3 monolingual language codes. Mirror of
    /// `DEEPGRAM_NOVA3_LANGUAGES` in proxy/src/index.js — keep in sync.
    /// Authoritative list (check periodically, Deepgram adds languages):
    ///   https://developers.deepgram.com/docs/models-languages-overview
    private static let deepgramNova3Languages: Set<TranscriptionLanguage> = [
        .ar, .bg, .bn, .ca, .cs, .da, .de, .el, .en, .es, .et, .fa, .fi, .fr, .he,
        .hi, .hr, .hu, .id, .it, .ja, .ko, .lt, .lv, .ms, .nl, .no, .pl, .pt, .ro,
        .ru, .sk, .sv, .ta, .te, .th, .tl, .tr, .uk, .ur, .vi, .zh,
    ]
}

struct Settings: Codable {
    var transcriptionProvider: TranscriptionProvider
    var cloudModel: CloudModel
    var transcriptionLanguage: TranscriptionLanguage
    var customVocabulary: String
    var removeFillerWords: Bool
    /// Speaker attribution, on-device Whisper only.
    var identifySpeakers: Bool
    /// Languages actually spoken, on-device Whisper only. Two or more makes each
    /// 30-second window pick between them instead of guessing from all 99.
    var spokenLanguages: [TranscriptionLanguage]
    /// Whether the extra languages and the dictionary are actually applied. Kept
    /// separate from the values so switching a feature off doesn't discard what
    /// the user typed.
    var useAdditionalLanguages: Bool
    var useDictionary: Bool
    var webhookURL: String?
    var webhookEnabled: Bool
    var webhookSecret: String
    var deviceId: String
    var appearanceMode: AppearanceMode

    /// Whether webhook delivery should run: a destination exists and it isn't paused.
    var isWebhookConfigured: Bool {
        guard webhookEnabled, let url = webhookURL else { return false }
        return !url.isEmpty
    }

    /// The dictionary to actually send, empty when the feature is switched off.
    var effectiveVocabulary: String {
        useDictionary ? customVocabulary : ""
    }

    /// The extra languages to actually use, empty when the feature is switched off.
    var effectiveAdditionalLanguages: [TranscriptionLanguage] {
        useAdditionalLanguages ? spokenLanguages : []
    }

    /// A destination is saved, whether or not delivery is currently paused.
    var hasWebhookDestination: Bool {
        guard let url = webhookURL else { return false }
        return !url.isEmpty
    }

    init(
        transcriptionProvider: TranscriptionProvider = .appleSpeech,
        cloudModel: CloudModel = .whisperLargeV3Turbo,
        transcriptionLanguage: TranscriptionLanguage = .auto,
        customVocabulary: String = "",
        removeFillerWords: Bool = false,
        identifySpeakers: Bool = false,
        spokenLanguages: [TranscriptionLanguage] = [],
        useAdditionalLanguages: Bool = false,
        useDictionary: Bool = false,
        webhookURL: String? = nil,
        webhookEnabled: Bool = true,
        webhookSecret: String = Self.generateSecret(),
        deviceId: String = UUID().uuidString,
        appearanceMode: AppearanceMode = .system
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.cloudModel = cloudModel
        self.transcriptionLanguage = transcriptionLanguage
        self.customVocabulary = customVocabulary
        self.removeFillerWords = removeFillerWords
        self.identifySpeakers = identifySpeakers
        self.spokenLanguages = spokenLanguages
        self.useAdditionalLanguages = useAdditionalLanguages
        self.useDictionary = useDictionary
        self.webhookURL = webhookURL
        self.webhookEnabled = webhookEnabled
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

        // Absent for anyone upgrading from a build without the pause switch, and
        // their destination was active, so default to on.
        webhookEnabled = try container.decodeIfPresent(Bool.self, forKey: .webhookEnabled) ?? true

        webhookSecret = try container.decodeIfPresent(String.self, forKey: .webhookSecret)
            ?? Self.generateSecret()

        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
            ?? UUID().uuidString

        cloudModel = try container.decodeIfPresent(CloudModel.self, forKey: .cloudModel)
            ?? .whisperLargeV3Turbo

        transcriptionLanguage = try container.decodeIfPresent(TranscriptionLanguage.self, forKey: .transcriptionLanguage)
            ?? .auto

        customVocabulary = try container.decodeIfPresent(String.self, forKey: .customVocabulary) ?? ""

        removeFillerWords = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? false

        identifySpeakers = try container.decodeIfPresent(Bool.self, forKey: .identifySpeakers) ?? false

        spokenLanguages = try container.decodeIfPresent([TranscriptionLanguage].self, forKey: .spokenLanguages) ?? []

        // Absent for anyone upgrading from before the switches existed, where a
        // stored value meant the feature was in use.
        useAdditionalLanguages = try container.decodeIfPresent(Bool.self, forKey: .useAdditionalLanguages)
            ?? !spokenLanguages.isEmpty
        useDictionary = try container.decodeIfPresent(Bool.self, forKey: .useDictionary)
            ?? !customVocabulary.isEmpty

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
        try container.encode(transcriptionLanguage, forKey: .transcriptionLanguage)
        try container.encode(customVocabulary, forKey: .customVocabulary)
        try container.encode(removeFillerWords, forKey: .removeFillerWords)
        try container.encode(identifySpeakers, forKey: .identifySpeakers)
        try container.encode(spokenLanguages, forKey: .spokenLanguages)
        try container.encode(useAdditionalLanguages, forKey: .useAdditionalLanguages)
        try container.encode(useDictionary, forKey: .useDictionary)
        try container.encodeIfPresent(webhookURL, forKey: .webhookURL)
        try container.encode(webhookEnabled, forKey: .webhookEnabled)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        // webhookSecret and deviceId are stored in Keychain, not on disk
    }

    static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case transcriptionProvider
        case cloudModel
        case transcriptionLanguage
        case customVocabulary
        case removeFillerWords
        case identifySpeakers
        case spokenLanguages
        case useAdditionalLanguages
        case useDictionary
        case webhookURL
        case webhookEnabled
        case webhookSecret
        case deviceId
        case appearanceMode
        // Legacy keys for migration
        case proxyBaseURL
        case apiBaseURL
        case apiToken
        case webhookAuthToken
    }
}
