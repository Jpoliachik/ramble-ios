//
//  WatchSyncQueue.swift
//  watch Watch App
//

import Combine
import Foundation

struct WatchSyncJob: Codable, Identifiable {
    let id: UUID
    let audioFileName: String
    let createdAt: Date
    let duration: TimeInterval
    var retryCount: Int = 0
    var lastAttemptAt: Date?
}

@MainActor
final class WatchSyncQueue: ObservableObject {
    static let shared = WatchSyncQueue()

    @Published private(set) var jobs: [WatchSyncJob] = []

    private static var queueFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watch_sync_queue.json")
    }

    private init() {
        loadQueue()
    }

    // MARK: - Public API

    func addJob(audioFileName: String, createdAt: Date, duration: TimeInterval) -> WatchSyncJob {
        let recordingId = UUID(
            uuidString: (audioFileName as NSString).deletingPathExtension
        ) ?? UUID()

        // Don't double-enqueue
        if let existing = jobs.first(where: { $0.id == recordingId }) {
            return existing
        }

        let job = WatchSyncJob(
            id: recordingId,
            audioFileName: audioFileName,
            createdAt: createdAt,
            duration: duration
        )
        jobs.append(job)
        saveQueue()
        return job
    }

    func markCompleted(jobId: UUID) {
        jobs.removeAll { $0.id == jobId }
        saveQueue()

        // Update recording history with sync timestamp
        WatchRecordingHistory.shared.markSynced(id: jobId)
    }

    func markFailed(jobId: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[idx].retryCount += 1
        jobs[idx].lastAttemptAt = Date()

        // Never give up and never delete the audio here: the watch may hold the
        // only copy. Retries are spaced out by WatchConnectivityService.

        saveQueue()
    }

    /// Returns all jobs that should be retried now
    func jobsNeedingRetry() -> [WatchSyncJob] {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        return jobs.filter { job in
            // Only retry if the audio file still exists
            let fileURL = documentsDir.appendingPathComponent(job.audioFileName)
            return FileManager.default.fileExists(atPath: fileURL.path)
        }
    }

    /// Remove jobs whose audio files no longer exist on disk (cleanup)
    func pruneOrphanedJobs() {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        jobs.removeAll { job in
            let fileURL = documentsDir.appendingPathComponent(job.audioFileName)
            let exists = FileManager.default.fileExists(atPath: fileURL.path)
            if !exists {
                print("WatchSyncQueue: pruning orphaned job \(job.id) — file missing")
            }
            return !exists
        }
        saveQueue()
    }

    // MARK: - Persistence

    private func loadQueue() {
        let url = Self.queueFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WatchSyncJob].self, from: data)
        else { return }
        jobs = decoded
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: Self.queueFileURL)
    }
}
