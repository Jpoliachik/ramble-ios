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

    /// In-memory copy of the last loaded/saved settings. Every write goes through
    /// `save`, so this stays authoritative, and it keeps `load()` cheap enough to
    /// call from a SwiftUI body.
    private var cached: Settings?

    private init() {}

    /// Rewrite the stored secret and device id with the current accessibility.
    ///
    /// Setting it on write only helps items that get written again, and these two
    /// normally never are: `load` seeds them once and then only reads. Without this
    /// an existing install keeps `WhenUnlocked` items that background work cannot
    /// read on a locked phone.
    func migrateKeychainAccessibilityIfNeeded() {
        let flag = "keychainAccessibilityMigrated"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        var migrated = true
        for key in [Self.webhookSecretKey, Self.deviceIdKey] {
            switch KeychainService.read(forKey: key) {
            case .found(let value):
                KeychainService.setString(value, forKey: key)
            case .notFound:
                continue
            case .unavailable:
                // Locked at launch. Leave the flag unset and try again next time.
                migrated = false
            }
        }

        if migrated {
            UserDefaults.standard.set(true, forKey: flag)
        }
    }

    func load() -> Settings {
        if let cached { return cached }

        var settings: Settings
        if let data = try? Data(contentsOf: settingsFile),
           let decoded = try? decoder.decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings.default
        }

        // Keychain is the source of truth for webhookSecret and deviceId. They are
        // seeded from the generated defaults only when genuinely absent: a read that
        // *failed* must never be treated as absence, or a load on a locked device
        // replaces the user's webhook secret with a new one and every later delivery
        // is signed with the wrong key.
        var needsSave = false
        var readFailed = false

        switch KeychainService.read(forKey: Self.webhookSecretKey) {
        case .found(let secret):
            settings.webhookSecret = secret
        case .notFound:
            KeychainService.setString(settings.webhookSecret, forKey: Self.webhookSecretKey)
            needsSave = true
        case .unavailable(let status):
            print("[Settings] webhook secret unreadable (OSStatus \(status)), keeping the stored one")
            readFailed = true
        }

        switch KeychainService.read(forKey: Self.deviceIdKey) {
        case .found(let deviceId):
            settings.deviceId = deviceId
        case .notFound:
            KeychainService.setString(settings.deviceId, forKey: Self.deviceIdKey)
            needsSave = true
        case .unavailable(let status):
            print("[Settings] device id unreadable (OSStatus \(status))")
            readFailed = true
        }

        if needsSave {
            guard let data = try? encoder.encode(settings) else { return settings }
            try? data.write(to: settingsFile)
        }

        // A partial read isn't cached, so the next load can pick up the real values
        // once the keychain is available again.
        if !readFailed {
            cached = settings
        }
        return settings
    }

    func save(_ settings: Settings) {
        cached = settings
        // Only touch the keychain when its current state is known. If a read failed,
        // whatever is in memory may be a freshly generated placeholder, and writing
        // it would destroy the real secret. Regenerating deliberately happens from
        // the UI, where the device is unlocked and reads succeed.
        writeIfVerifiable(settings.webhookSecret, forKey: Self.webhookSecretKey)
        writeIfVerifiable(settings.deviceId, forKey: Self.deviceIdKey)

        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsFile)
    }

    private func writeIfVerifiable(_ value: String, forKey key: String) {
        switch KeychainService.read(forKey: key) {
        case .found, .notFound:
            KeychainService.setString(value, forKey: key)
        case .unavailable(let status):
            print("[Settings] not writing \(key), keychain unreadable (OSStatus \(status))")
        }
    }
}
