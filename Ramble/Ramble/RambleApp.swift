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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    init() {
        BackgroundTaskService.shared.registerBackgroundTasks()
        AppAttestService.shared.migrateKeychainAccessibilityIfNeeded()
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
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(
                    AppearanceMode(rawValue: appearanceMode)?.colorScheme
                )
                .sheet(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { isPresented in
                        if !isPresented { hasCompletedOnboarding = true }
                    }
                )) {
                    OnboardingView()
                        .interactiveDismissDisabled()
                }
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
