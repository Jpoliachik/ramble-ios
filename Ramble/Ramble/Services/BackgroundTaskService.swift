//
//  BackgroundTaskService.swift
//  Ramble
//
//  Background time for the phone's own work: uploading its notes, the
//  check-in with Ramble's server (transcripts, delivery state, account) and
//  webhooks. Uploads run on URLSession inside a UIKit background task, with
//  a BGProcessingTask and periodic app refresh as fallbacks.
//

import BackgroundTasks
import Foundation
import UIKit

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    static let syncTaskIdentifier = "dev.goodloop.ramble.sync"
    /// Periodic check-in: collects transcripts of watch notes, and launching
    /// activates WatchConnectivity, which hands over any queued watch audio.
    static let refreshTaskIdentifier = "dev.goodloop.ramble.refresh"
    private static let refreshInterval: TimeInterval = 15 * 60

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncTaskIdentifier,
            using: nil
        ) { task in
            self.handleSyncTask(task as! BGProcessingTask)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleRefreshTask(task as! BGAppRefreshTask)
        }
    }

    // MARK: - Shared work

    @MainActor
    private var hasActiveWork: Bool {
        UploadQueueService.shared.hasActiveWork
            || WebhookQueueService.shared.hasActiveWork
            || NoteSyncService.shared.hasActiveWork
    }

    /// Kick everything once, then check in with the server.
    @MainActor
    private func runOnce(appOpened: Bool = false) async {
        UploadQueueService.shared.resume(appOpened: appOpened)
        WebhookQueueService.shared.resumePendingJobs()
        await NoteSyncService.shared.checkIn()
    }

    // MARK: - App refresh

    func scheduleRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(Self.refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[Background] Failed to schedule app refresh: \(error)")
        }
    }

    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        scheduleRefreshTask()

        let workTask = Task { @MainActor in
            await PhoneConnectivityService.shared.waitForPendingWatchContent()
            await self.runOnce()
            let deadline = Date().addingTimeInterval(20)
            while self.hasActiveWork && Date() < deadline && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Immediate Background Processing

    /// Holds the background task open even with no queued work, so a file
    /// the watch is about to deliver lands while Ramble is still awake.
    private var keepAliveUntil: Date = .distantPast

    /// Begin a UIKit background task (~30s) and run the queues and a
    /// check-in. Called on entering the background, on unlock, and when the
    /// watch wakes Ramble. `keepAliveFor` keeps it running that long even
    /// with nothing queued.
    @MainActor
    func beginImmediateBackgroundProcessing(keepAliveFor: TimeInterval = 0) {
        if keepAliveFor > 0 {
            keepAliveUntil = max(keepAliveUntil, Date().addingTimeInterval(keepAliveFor))
        }
        guard backgroundTaskID == .invalid else {
            // Already running; still collect whatever just arrived.
            Task { @MainActor in await self.runOnce() }
            return
        }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "RambleSync") {
            // UIKit calls this on the main thread.
            MainActor.assumeIsolated {
                self.endImmediateBackgroundProcessing()
            }
        }
        guard backgroundTaskID != .invalid else { return }

        Task { @MainActor in
            await self.runOnce()
            while self.hasActiveWork || Date() < self.keepAliveUntil {
                if UIApplication.shared.backgroundTimeRemaining < 5 { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            self.endImmediateBackgroundProcessing()
        }
    }

    /// Ramble opened or came back to the foreground.
    @MainActor
    func appDidOpen() {
        Task { await runOnce(appOpened: true) }
    }

    /// Pull to refresh on Home: same as opening Ramble.
    @MainActor
    func refresh() async {
        await runOnce(appOpened: true)
    }

    @MainActor
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
        } catch {
            print("[Background] Failed to schedule BGProcessingTask: \(error)")
        }
    }

    private func handleSyncTask(_ task: BGProcessingTask) {
        scheduleSyncTask()

        let workTask = Task { @MainActor in
            await self.runOnce()
            let deadline = Date().addingTimeInterval(25)
            while self.hasActiveWork && Date() < deadline && !Task.isCancelled {
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
