//
//  BackgroundTaskService.swift
//  Ramble
//

import BackgroundTasks
import Foundation

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    static let transcriptionTaskIdentifier = "dev.goodloop.ramble.transcription"

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.transcriptionTaskIdentifier,
            using: nil
        ) { task in
            self.handleTranscriptionTask(task as! BGProcessingTask)
        }
    }

    func scheduleTranscriptionTask() {
        let request = BGProcessingTaskRequest(identifier: Self.transcriptionTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background task scheduled")
        } catch {
            print("Failed to schedule background task: \(error)")
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
