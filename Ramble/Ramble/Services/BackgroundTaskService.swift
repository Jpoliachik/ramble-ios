//
//  BackgroundTaskService.swift
//  Ramble
//

import BackgroundTasks
import Foundation
import UIKit

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    static let syncTaskIdentifier = "dev.goodloop.ramble.sync"

    /// Tracks the current UIKit background task (for immediate ~30s execution)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncTaskIdentifier,
            using: nil
        ) { task in
            self.handleSyncTask(task as! BGProcessingTask)
        }
    }

    // MARK: - Immediate Background Processing

    /// Holds the background task open even with no queued work, so a file
    /// the watch is about to deliver lands while Ramble is still awake.
    private var keepAliveUntil: Date = .distantPast

    private var hasActiveWork: Bool {
        TranscriptionQueueService.shared.hasActiveWork
            || WebhookQueueService.shared.hasActiveWork
            || RelayQueueService.shared.hasActiveWork
    }

    /// Begin a UIKit background task for immediate execution time (~30s).
    /// Call this when entering background to finish in-flight transcription + webhook work.
    /// `keepAliveFor` keeps it running that long even when the queues are
    /// empty (used when the watch wakes Ramble ahead of a file).
    func beginImmediateBackgroundProcessing(keepAliveFor: TimeInterval = 0) {
        if keepAliveFor > 0 {
            keepAliveUntil = max(keepAliveUntil, Date().addingTimeInterval(keepAliveFor))
        }
        guard backgroundTaskID == .invalid else {
            print("[Background] Immediate background task already active")
            return
        }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "RambleSync") {
            print("[Background] Immediate background task expired")
            self.endImmediateBackgroundProcessing()
        }

        guard backgroundTaskID != .invalid else {
            print("[Background] Failed to begin immediate background task")
            return
        }

        print("[Background] Immediate background task started (remaining: \(String(format: "%.0f", UIApplication.shared.backgroundTimeRemaining))s)")

        Task { @MainActor in
            let transcriptionQueue = TranscriptionQueueService.shared
            let webhookQueue = WebhookQueueService.shared
            let relayQueue = RelayQueueService.shared

            transcriptionQueue.resumePendingJobs()
            webhookQueue.resumePendingJobs()
            relayQueue.resumePendingJobs()

            // Loops again if work arrived while pickups were refreshing,
            // since a second call returns early while this task is open.
            var outOfTime = false
            repeat {
                while self.hasActiveWork || Date() < self.keepAliveUntil {
                    let remaining = UIApplication.shared.backgroundTimeRemaining
                    if remaining < 5 {
                        print("[Background] Running low on time (\(String(format: "%.0f", remaining))s), stopping")
                        outOfTime = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                if !outOfTime, UIApplication.shared.backgroundTimeRemaining > 10 {
                    await relayQueue.refreshPickups()
                }
                DeliveryMonitor.shared.evaluate()
            } while !outOfTime && self.hasActiveWork

            print("[Background] Immediate background processing finished")
            self.endImmediateBackgroundProcessing()
        }
    }

    private func endImmediateBackgroundProcessing() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Deferred BGProcessingTask

    func scheduleSyncTask() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[Background] BGProcessingTask scheduled")
        } catch {
            print("[Background] Failed to schedule BGProcessingTask: \(error)")
        }
    }

    private func handleSyncTask(_ task: BGProcessingTask) {
        scheduleSyncTask()

        let workTask = Task { @MainActor in
            let transcriptionQueue = TranscriptionQueueService.shared
            let webhookQueue = WebhookQueueService.shared
            let relayQueue = RelayQueueService.shared

            transcriptionQueue.resumePendingJobs()
            webhookQueue.resumePendingJobs()
            relayQueue.resumePendingJobs()

            let deadline = Date().addingTimeInterval(25)
            while (transcriptionQueue.hasActiveWork || webhookQueue.hasActiveWork || relayQueue.hasActiveWork) && Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await relayQueue.refreshPickups()
            DeliveryMonitor.shared.evaluate()
        }

        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: true)
        }
    }
}
