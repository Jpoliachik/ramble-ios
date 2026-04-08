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
        var needsSave = false

        if let keychainSecret = KeychainService.string(forKey: Self.webhookSecretKey) {
            settings.webhookSecret = keychainSecret
        } else {
            KeychainService.setString(settings.webhookSecret, forKey: Self.webhookSecretKey)
            needsSave = true
        }

        if let keychainDeviceId = KeychainService.string(forKey: Self.deviceIdKey) {
            settings.deviceId = keychainDeviceId
        } else {
            KeychainService.setString(settings.deviceId, forKey: Self.deviceIdKey)
            needsSave = true
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
