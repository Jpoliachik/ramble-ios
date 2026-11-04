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

    /// False while the phone is locked and the webhook secret or device id
    /// can't be read. Work that signs or identifies requests waits for unlock.
    var secretsAvailable: Bool {
        KeychainService.lookup(forKey: Self.webhookSecretKey) != .locked
            && KeychainService.lookup(forKey: Self.deviceIdKey) != .locked
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
        // returned here are throwaway placeholders: check `secretsAvailable`
        // before using them.
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
