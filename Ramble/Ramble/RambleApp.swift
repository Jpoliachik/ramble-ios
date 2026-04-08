//
//  RambleApp.swift
//  Ramble
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct RambleApp: App {
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
    }

    var body: some Scene {
        WindowGroup {
            MainView()
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
