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

/// Language hint, kept with the inbox on the server (GET/PUT /settings).
/// `.auto` lets the provider detect it; other cases are ISO 639-1 codes.
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

struct Settings: Codable {
    var transcriptionLanguage: TranscriptionLanguage
    var customVocabulary: String
    var removeFillerWords: Bool
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
        transcriptionLanguage: TranscriptionLanguage = .auto,
        customVocabulary: String = "",
        removeFillerWords: Bool = false,
        webhookURL: String? = nil,
        webhookSecret: String = Self.generateSecret(),
        deviceId: String = UUID().uuidString,
        appearanceMode: AppearanceMode = .system
    ) {
        self.transcriptionLanguage = transcriptionLanguage
        self.customVocabulary = customVocabulary
        self.removeFillerWords = removeFillerWords
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

        transcriptionLanguage = (try? container.decodeIfPresent(TranscriptionLanguage.self, forKey: .transcriptionLanguage))
            ?? .auto

        customVocabulary = try container.decodeIfPresent(String.self, forKey: .customVocabulary) ?? ""

        removeFillerWords = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? false

        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)
            ?? .system
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transcriptionLanguage, forKey: .transcriptionLanguage)
        try container.encode(customVocabulary, forKey: .customVocabulary)
        try container.encode(removeFillerWords, forKey: .removeFillerWords)
        try container.encodeIfPresent(webhookURL, forKey: .webhookURL)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        // webhookSecret and deviceId are stored in Keychain, not on disk
    }

    static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case transcriptionLanguage
        case customVocabulary
        case removeFillerWords
        case webhookURL
        case webhookSecret
        case deviceId
        case appearanceMode
    }
}
