//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiBaseURL: String = ""
    @Published var apiToken: String = ""
    @Published var totalRecordings: Int = 0
    @Published var totalDuration: TimeInterval = 0

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared

    init() {
        load()
    }

    func load() {
        let settings = settingsService.load()
        apiBaseURL = settings.apiBaseURL ?? ""
        apiToken = settings.apiToken ?? ""
        loadStats()
    }

    func save() {
        let settings = Settings(
            apiBaseURL: apiBaseURL.isEmpty ? nil : apiBaseURL,
            apiToken: apiToken.isEmpty ? nil : apiToken
        )
        settingsService.save(settings)
    }

    private func loadStats() {
        let recordings = storageService.loadRecordings()
        totalRecordings = recordings.count
        totalDuration = recordings.reduce(0) { $0 + $1.duration }
    }

    func exportJSON() -> URL? {
        let recordings = storageService.loadRecordings()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(recordings) else { return nil }

        let exportURL = StorageService.documentsDirectory
            .appendingPathComponent("ramble_export.json")
        try? data.write(to: exportURL)
        return exportURL
    }

    func deleteAllData() {
        storageService.deleteAllRecordings()
        loadStats()
    }
}
