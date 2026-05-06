//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    /// Hard cap on the custom-vocabulary field. Whisper's `prompt` accepts up
    /// to ~224 tokens (~900 chars); beyond that the provider silently
    /// truncates. We clamp on input so the user sees the limit instead of
    /// getting silently lossy hints.
    static let maxVocabularyLength = 900

    @Published var transcriptionProvider: TranscriptionProvider = .appleSpeech {
        didSet { resetLanguageIfUnsupported() }
    }
    @Published var cloudModel: CloudModel = .whisperLargeV3Turbo {
        didSet { resetLanguageIfUnsupported() }
    }
    @Published var transcriptionLanguage: TranscriptionLanguage = .auto
    @Published var customVocabulary: String = "" {
        didSet {
            if customVocabulary.count > Self.maxVocabularyLength {
                customVocabulary = String(customVocabulary.prefix(Self.maxVocabularyLength))
            }
        }
    }
    @Published var removeFillerWords: Bool = false
    @Published var showSubscriptionPaywall = false
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
    @Published var devOverrideKey: String = ""

    /// The cloud model the user tapped before being shown the paywall
    private var pendingCloudModel: CloudModel?

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        // When the paywall dismisses, apply the pending cloud model if the user subscribed
        $showSubscriptionPaywall
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.applyPendingCloudModel()
            }
            .store(in: &cancellables)

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
        transcriptionProvider = settings.transcriptionProvider
        cloudModel = settings.cloudModel
        transcriptionLanguage = settings.transcriptionLanguage
        customVocabulary = settings.customVocabulary
        removeFillerWords = settings.removeFillerWords
        webhookURL = settings.webhookURL ?? ""
        webhookSecret = settings.webhookSecret
        deviceId = settings.deviceId
        appearanceMode = settings.appearanceMode
        devOverrideKey = UserDefaults.standard.string(forKey: SubscriptionService.devOverrideUserDefaultsKey) ?? ""
        loadStats()
    }

    func save() {
        let settings = Settings(
            transcriptionProvider: transcriptionProvider,
            cloudModel: cloudModel,
            transcriptionLanguage: transcriptionLanguage,
            customVocabulary: customVocabulary,
            removeFillerWords: removeFillerWords,
            webhookURL: webhookURL.isEmpty ? nil : webhookURL,
            webhookSecret: webhookSecret,
            deviceId: deviceId,
            appearanceMode: appearanceMode
        )
        settingsService.save(settings)

        let key = devOverrideKey.trimmingCharacters(in: .whitespacesAndNewlines)
        SubscriptionService.shared.setDevOverrideKey(key.isEmpty ? nil : key)
    }

    func selectCloudTranscription() {
        if SubscriptionService.shared.isPremium {
            transcriptionProvider = .cloudTranscription
        } else {
            showSubscriptionPaywall = true
        }
    }

    func selectCloudModel(_ model: CloudModel) {
        if SubscriptionService.shared.isPremium {
            transcriptionProvider = .cloudTranscription
            cloudModel = model
        } else {
            pendingCloudModel = model
            showSubscriptionPaywall = true
        }
    }

    /// When the cloud model changes to one that doesn't support the user's
    /// previously chosen language (e.g. Welsh on Whisper → Nova-3), demote
    /// the picker back to `.auto` so we never silently send an unsupported hint.
    private func resetLanguageIfUnsupported() {
        guard transcriptionLanguage != .auto else { return }
        guard transcriptionProvider.isCloud else { return }
        if !cloudModel.supports(transcriptionLanguage) {
            transcriptionLanguage = .auto
        }
    }

    private func applyPendingCloudModel() {
        guard let model = pendingCloudModel else { return }
        pendingCloudModel = nil
        if SubscriptionService.shared.isPremium {
            transcriptionProvider = .cloudTranscription
            cloudModel = model
        }
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
        pendingTranscriptions = recordings.filter { [.recorded, .transcribing].contains($0.status) }.count
        failedTranscriptions = recordings.filter { $0.status == .failed }.count
        webhookHealth = WebhookHealth.compute(from: recordings)
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
