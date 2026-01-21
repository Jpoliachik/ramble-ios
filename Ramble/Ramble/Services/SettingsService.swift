//
//  SettingsService.swift
//  Ramble
//

import Foundation

final class SettingsService {
    static let shared = SettingsService()

    private let settingsFile = StorageService.documentsDirectory
        .appendingPathComponent("settings.json")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func load() -> Settings {
        guard FileManager.default.fileExists(atPath: settingsFile.path),
              let data = try? Data(contentsOf: settingsFile),
              let settings = try? decoder.decode(Settings.self, from: data) else {
            let defaultSettings = Settings.default
            save(defaultSettings)
            return defaultSettings
        }
        return settings
    }

    func save(_ settings: Settings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
}
