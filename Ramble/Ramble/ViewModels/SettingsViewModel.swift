//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var webhookURL: String = ""
    @Published var webhookAuthToken: String = ""
    @Published var qualityThreshold: Double = 0.6
    @Published var totalRecordings: Int = 0
    @Published var totalDuration: TimeInterval = 0

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared

    init() {
        load()
    }

    func load() {
        let settings = settingsService.load()
        webhookURL = settings.webhookURL ?? ""
        webhookAuthToken = settings.webhookAuthToken ?? ""
        qualityThreshold = settings.transcriptionQualityThreshold
        loadStats()
    }

    func save() {
        let settings = Settings(
            webhookURL: webhookURL.isEmpty ? nil : webhookURL,
            webhookAuthToken: webhookAuthToken.isEmpty ? nil : webhookAuthToken,
            transcriptionQualityThreshold: qualityThreshold
        )
        settingsService.save(settings)
    }

    private func loadStats() {
        let recordings = storageService.loadRecordings()
        totalRecordings = recordings.count
        totalDuration = recordings.reduce(0) { $0 + $1.duration }
    }

    var estimatedCost: Double {
        let hours = totalDuration / 3600
        return hours * Constants.costPerHour
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
