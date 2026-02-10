//
//  BackgroundTaskService.swift
//  Ramble
//

import BackgroundTasks
import Foundation
import UIKit

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    static let transcriptionTaskIdentifier = "dev.goodloop.ramble.transcription"

    /// Tracks the current UIKit background task (for immediate ~30s execution)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.transcriptionTaskIdentifier,
            using: nil
        ) { task in
            self.handleTranscriptionTask(task as! BGProcessingTask)
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

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "RambleTranscription") {
            // Expiration handler — system is about to suspend us
            print("[Background] Immediate background task expired")
            self.endImmediateBackgroundProcessing()
        }

        guard backgroundTaskID != .invalid else {
            print("[Background] Failed to begin immediate background task")
            return
        }

        print("[Background] Immediate background task started (remaining: \(String(format: "%.0f", UIApplication.shared.backgroundTimeRemaining))s)")

        Task { @MainActor in
            let queue = TranscriptionQueueService.shared

            // Process any pending transcriptions + webhook retries
            queue.resumePendingJobs()

            // Poll until all work is done or we're running low on time
            while queue.hasActiveWork {
                let remaining = UIApplication.shared.backgroundTimeRemaining
                if remaining < 5 {
                    print("[Background] Running low on time (\(String(format: "%.0f", remaining))s), stopping poll")
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // check every 0.5s
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

    // MARK: - Deferred BGProcessingTask (fallback for retries)

    func scheduleTranscriptionTask() {
        let request = BGProcessingTaskRequest(identifier: Self.transcriptionTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[Background] BGProcessingTask scheduled")
        } catch {
            print("[Background] Failed to schedule BGProcessingTask: \(error)")
        }
    }

    private func handleTranscriptionTask(_ task: BGProcessingTask) {
        // Re-schedule so we keep running while there's pending work
        scheduleTranscriptionTask()

        let workTask = Task { @MainActor in
            let queue = TranscriptionQueueService.shared

            // Process pending transcriptions
            queue.resumePendingJobs()

            // Wait for processing with a timeout (up to 25s to leave margin)
            let deadline = Date().addingTimeInterval(25)
            while queue.isProcessing && Date() < deadline {
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
