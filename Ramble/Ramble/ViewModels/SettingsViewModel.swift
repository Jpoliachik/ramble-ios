//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var transcriptionProvider: TranscriptionProvider = .appleSpeech
    @Published var webhookEnabled: Bool = false
    @Published var webhookURL: String = ""
    @Published var webhookSecret: String = ""
    @Published var deviceId: String = ""
    @Published var totalRecordings: Int = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var pendingTranscriptions: Int = 0
    @Published var failedTranscriptions: Int = 0

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared

    init() {
        load()
    }

    func load() {
        let settings = settingsService.load()
        transcriptionProvider = settings.transcriptionProvider
        webhookEnabled = settings.webhookEnabled
        webhookURL = settings.webhookURL ?? ""
        webhookSecret = settings.webhookSecret
        deviceId = settings.deviceId
        loadStats()
    }

    func save() {
        let settings = Settings(
            transcriptionProvider: transcriptionProvider,
            webhookEnabled: webhookEnabled,
            webhookURL: webhookURL.isEmpty ? nil : webhookURL,
            webhookSecret: webhookSecret,
            deviceId: deviceId
        )
        settingsService.save(settings)
    }

    func regenerateWebhookSecret() {
        webhookSecret = Settings.generateSecret()
    }

    private func loadStats() {
        let recordings = storageService.loadRecordings()
        totalRecordings = recordings.count
        totalDuration = recordings.reduce(0) { $0 + $1.duration }
        pendingTranscriptions = recordings.filter { [.recorded, .transcribing].contains($0.status) }.count
        failedTranscriptions = recordings.filter { $0.status == .failed }.count
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
