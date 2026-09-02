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

    /// Begin a UIKit background task for immediate execution time (~30s).
    /// Call this when entering background to finish in-flight transcription + webhook work.
    func beginImmediateBackgroundProcessing() {
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

            transcriptionQueue.resumePendingJobs()
            webhookQueue.resumePendingJobs()

            while transcriptionQueue.hasActiveWork || webhookQueue.hasActiveWork {
                let remaining = UIApplication.shared.backgroundTimeRemaining
                if remaining < 5 {
                    print("[Background] Running low on time (\(String(format: "%.0f", remaining))s), stopping")
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

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

            transcriptionQueue.resumePendingJobs()
            webhookQueue.resumePendingJobs()

            // No self-imposed deadline. A BGProcessingTask is given far longer than
            // the ~30s of a UIKit assertion, and the system tells us when to stop
            // through `expirationHandler`. Cutting this off at 25s meant an
            // on-device transcription, where loading the model alone can take
            // minutes on first use, could never finish here.
            while transcriptionQueue.hasActiveWork || webhookQueue.hasActiveWork {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
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
