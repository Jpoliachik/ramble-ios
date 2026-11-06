//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    /// The relay's limit on the vocabulary field (relay-api.md "Transcription settings").
    static let maxVocabularyLength = 900

    @Published var transcriptionLanguage: TranscriptionLanguage = .auto
    @Published var customVocabulary: String = "" {
        didSet {
            if customVocabulary.count > Self.maxVocabularyLength {
                customVocabulary = String(customVocabulary.prefix(Self.maxVocabularyLength))
            }
        }
    }
    @Published var removeFillerWords: Bool = false
    @Published var webhookURL: String = ""
    @Published var webhookSecret: String = ""
    @Published var deviceId: String = ""
    @Published var totalRecordings: Int = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var pendingTranscriptions: Int = 0
    @Published var failedTranscriptions: Int = 0
    @Published var webhookHealth: WebhookHealth = .untested
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            // Sync to UserDefaults immediately so @AppStorage in RambleApp updates in real time
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }
    @Published var webhookURLError: String?
    #if DEBUG
    @Published var devOverrideKey: String = ""
    #endif

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        NotificationCenter.default
            .publisher(for: StorageService.recordingsDidChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadStats()
            }
            .store(in: &cancellables)
    }

    func load() {
        let settings = settingsService.load()
        transcriptionLanguage = settings.transcriptionLanguage
        customVocabulary = settings.customVocabulary
        removeFillerWords = settings.removeFillerWords
        webhookURL = settings.webhookURL ?? ""
        webhookSecret = settings.webhookSecret
        deviceId = settings.deviceId
        appearanceMode = settings.appearanceMode
        #if DEBUG
        devOverrideKey = UserDefaults.standard.string(forKey: Constants.Relay.devBypassKey) ?? ""
        #endif
        loadStats()
    }

    /// Reads the server's transcription settings into the form.
    func pullTranscriptionSettings() async {
        await NoteSyncService.shared.pullTranscriptionSettings()
        let settings = settingsService.load()
        transcriptionLanguage = settings.transcriptionLanguage
        customVocabulary = settings.customVocabulary
        removeFillerWords = settings.removeFillerWords
    }

    func save() {
        let previous = settingsService.load()
        var settings = previous
        settings.transcriptionLanguage = transcriptionLanguage
        settings.customVocabulary = customVocabulary
        settings.removeFillerWords = removeFillerWords
        settings.webhookURL = webhookURL.isEmpty ? nil : webhookURL
        settings.webhookSecret = webhookSecret
        settings.appearanceMode = appearanceMode
        settingsService.save(settings)

        let transcriptionChanged = previous.transcriptionLanguage != settings.transcriptionLanguage
            || previous.customVocabulary != settings.customVocabulary
            || previous.removeFillerWords != settings.removeFillerWords
        if transcriptionChanged {
            // Kept with the inbox, so both devices' notes use them.
            settingsService.transcriptionSettingsDirty = true
            Task { await NoteSyncService.shared.pushTranscriptionSettingsIfNeeded() }
        }

        #if DEBUG
        let key = devOverrideKey.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(key.isEmpty ? nil : key, forKey: Constants.Relay.devBypassKey)
        #endif
    }

    func validateWebhookURL() {
        if webhookURL.isEmpty {
            webhookURLError = nil
            return
        }
        webhookURLError = WebhookQueueService.validateWebhookURL(webhookURL)
    }

    func regenerateWebhookSecret() {
        webhookSecret = Settings.generateSecret()
    }

    private func loadStats() {
        let recordings = storageService.loadRecordings()
        totalRecordings = recordings.count
        totalDuration = recordings.reduce(0) { $0 + $1.duration }
        pendingTranscriptions = recordings.filter {
            ($0.status == .recorded || $0.status == .transcribing) && $0.hold != .tooLong && $0.hold != .couldntSend
        }.count
        failedTranscriptions = recordings.filter { $0.status == .failed }.count
        webhookHealth = WebhookHealth.compute(from: recordings)
    }

    func exportJSON() -> URL? {
        let recordings = storageService.loadRecordings()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(recordings) else { return nil }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ramble_export.json")
        try? data.write(to: exportURL)
        return exportURL
    }

    /// Removes every note from this iPhone for good. Agents, their waiting
    /// copies, the free count and the unlock are untouched.
    func deleteAllData() {
        storageService.deleteAllRecordings()
        loadStats()
    }
}
