//
//  SettingsService.swift
//  Ramble
//

import Foundation

final class SettingsService {
    static let shared = SettingsService()

    private static let webhookSecretKey = "webhookSecret"
    private static let deviceIdKey = "deviceId"

    private let settingsFile = StorageService.documentsDirectory
        .appendingPathComponent("settings.json")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    private static let transcriptionSettingsDirtyKey = "transcriptionSettingsDirty"

    /// Language, vocabulary or filler words changed here and the server
    /// hasn't confirmed it yet. Sent again on the next check-in.
    var transcriptionSettingsDirty: Bool {
        get { UserDefaults.standard.bool(forKey: Self.transcriptionSettingsDirtyKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.transcriptionSettingsDirtyKey) }
    }

    func load() -> Settings {
        var settings: Settings
        if let data = try? Data(contentsOf: settingsFile),
           let decoded = try? decoder.decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings.default
        }

        // Keychain is the source of truth for webhookSecret and deviceId.
        // On first launch these won't exist yet, so we seed from the generated defaults.
        // While the phone is locked they can't be read, and the values
        // returned here are throwaway placeholders: work that uses them waits
        // on `KeychainService.isLocked`.
        var needsSave = false

        switch KeychainService.lookup(forKey: Self.webhookSecretKey) {
        case .found(let keychainSecret):
            settings.webhookSecret = keychainSecret
        case .notFound:
            KeychainService.setString(settings.webhookSecret, forKey: Self.webhookSecretKey)
            needsSave = true
        case .locked:
            break
        }

        switch KeychainService.lookup(forKey: Self.deviceIdKey) {
        case .found(let keychainDeviceId):
            settings.deviceId = keychainDeviceId
        case .notFound:
            KeychainService.setString(settings.deviceId, forKey: Self.deviceIdKey)
            needsSave = true
        case .locked:
            break
        }

        if needsSave {
            guard let data = try? encoder.encode(settings) else { return settings }
            try? data.write(to: settingsFile)
        }
        return settings
    }

    func save(_ settings: Settings) {
        KeychainService.setString(settings.webhookSecret, forKey: Self.webhookSecretKey)
        KeychainService.setString(settings.deviceId, forKey: Self.deviceIdKey)

        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
}
