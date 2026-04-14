//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var transcriptionProvider: TranscriptionProvider = .appleSpeech
    @Published var cloudModel: CloudModel = .whisperLargeV3Turbo
    @Published var showSubscriptionPaywall = false
    @Published var webhookEnabled: Bool = false
    @Published var webhookURL: String = ""
    @Published var webhookSecret: String = ""
    @Published var deviceId: String = ""
    @Published var totalRecordings: Int = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var pendingTranscriptions: Int = 0
    @Published var failedTranscriptions: Int = 0
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            // Sync to UserDefaults immediately so @AppStorage in RambleApp updates in real time
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }
    @Published var webhookURLError: String?
    @Published var testWebhookResult: TestWebhookResult?
    @Published var devOverrideKey: String = ""

    enum TestWebhookResult {
        case loading
        case success
        case failure(String)
    }

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
    }

    func load() {
        let settings = settingsService.load()
        transcriptionProvider = settings.transcriptionProvider
        cloudModel = settings.cloudModel
        webhookEnabled = settings.webhookEnabled
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
            webhookEnabled: webhookEnabled,
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

    func sendTestWebhook() {
        // Validate first
        validateWebhookURL()
        guard webhookURLError == nil, !webhookURL.isEmpty else { return }

        // Save current settings so the test uses latest values
        save()

        testWebhookResult = .loading
        Task {
            let error = await WebhookQueueService.shared.sendTestWebhook()
            if let error {
                testWebhookResult = .failure(error)
            } else {
                testWebhookResult = .success
            }
            // Auto-dismiss success after a delay
            if case .success = testWebhookResult {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if case .success = testWebhookResult {
                    testWebhookResult = nil
                }
            }
        }
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
