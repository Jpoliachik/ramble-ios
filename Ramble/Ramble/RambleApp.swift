//
//  RambleApp.swift
//  Ramble
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct RambleApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        BackgroundTaskService.shared.registerBackgroundTasks()
        _ = PhoneConnectivityService.shared
        HapticService.prepare()

        // Proactively download the speech model so transcription works immediately
        Task {
            await TranscriptionQueueService.shared.prepareModelIfNeeded()
        }

        // Initialize subscription service and fetch products
        Task {
            await SubscriptionService.shared.start()
        }

        // Returning users (existing recordings or configured webhook) skip onboarding
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            let hasRecordings = !StorageService.shared.loadRecordings().isEmpty
            let hasWebhook = SettingsService.shared.load().webhookURL?.isEmpty == false
            if hasRecordings || hasWebhook {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainView()
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
                .animation(.easeInOut(duration: 0.35), value: hasCompletedOnboarding)
                .preferredColorScheme(
                    AppearanceMode(rawValue: appearanceMode)?.colorScheme
                )
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    // Immediate ~30s background time for in-flight transcription + webhook
                    BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
                    // Also schedule deferred BGProcessingTask as fallback
                    BackgroundTaskService.shared.scheduleSyncTask()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    TranscriptionQueueService.shared.resumePendingJobs()
                    WebhookQueueService.shared.resumePendingJobs()
                }
        }
    }
}
