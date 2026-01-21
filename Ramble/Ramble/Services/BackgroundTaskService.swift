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
            print("Background transcription task scheduled")
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }

    private func handleTranscriptionTask(_ task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            TranscriptionQueueService.shared.resumePendingJobs()

            // Give some time for processing
            try? await Task.sleep(nanoseconds: 30_000_000_000)

            task.setTaskCompleted(success: true)
        }
    }
}
