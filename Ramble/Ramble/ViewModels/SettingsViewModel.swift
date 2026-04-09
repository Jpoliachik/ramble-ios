//
//  SettingsViewModel.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var transcriptionProvider: TranscriptionProvider = .appleSpeech
    @Published var cloudModel: CloudModel = .whisperLargeV3Turbo
    @Published var customEndpointURL: String = ""
    @Published var customEndpointAuthHeader: String = ""
    @Published var customEndpointURLError: String?
    @Published var showSubscriptionPaywall = false
    @Published var webhookEnabled: Bool = false
    @Published var webhookURL: String = ""
    @Published var webhookSecret: String = ""
    @Published var deviceId: String = ""
    @Published var totalRecordings: Int = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var pendingTranscriptions: Int = 0
    @Published var failedTranscriptions: Int = 0
    @Published var webhookURLError: String?
    @Published var testWebhookResult: TestWebhookResult?

    enum TestWebhookResult {
        case loading
        case success
        case failure(String)
    }

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared

    init() {
        load()
    }

    func load() {
        let settings = settingsService.load()
        transcriptionProvider = settings.transcriptionProvider
        cloudModel = settings.cloudModel
        customEndpointURL = settings.customEndpointURL ?? ""
        customEndpointAuthHeader = settings.customEndpointAuthHeader ?? ""
        webhookEnabled = settings.webhookEnabled
        webhookURL = settings.webhookURL ?? ""
        webhookSecret = settings.webhookSecret
        deviceId = settings.deviceId
        loadStats()
    }

    func save() {
        let settings = Settings(
            transcriptionProvider: transcriptionProvider,
            cloudModel: cloudModel,
            customEndpointURL: customEndpointURL.isEmpty ? nil : customEndpointURL,
            customEndpointAuthHeader: customEndpointAuthHeader.isEmpty ? nil : customEndpointAuthHeader,
            webhookEnabled: webhookEnabled,
            webhookURL: webhookURL.isEmpty ? nil : webhookURL,
            webhookSecret: webhookSecret,
            deviceId: deviceId
        )
        settingsService.save(settings)
    }

    func selectCloudTranscription() {
        if SubscriptionService.shared.isPremium {
            transcriptionProvider = .cloudTranscription
        } else {
            showSubscriptionPaywall = true
        }
    }

    func validateCustomEndpointURL() {
        if customEndpointURL.isEmpty {
            customEndpointURLError = nil
            return
        }
        guard let url = URL(string: customEndpointURL) else {
            customEndpointURLError = "Invalid URL format"
            return
        }
        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" else {
            customEndpointURLError = "URL must use HTTP or HTTPS"
            return
        }
        guard url.host != nil, !url.host!.isEmpty else {
            customEndpointURLError = "URL must include a hostname"
            return
        }
        customEndpointURLError = nil
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
