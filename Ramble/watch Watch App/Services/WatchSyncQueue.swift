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

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isSyncing: Bool = false

    private(set) var jobs: [WatchSyncJob] = []

    private static let maxRetries = 50

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
        pendingCount = jobs.count
        saveQueue()
        return job
    }

    func markCompleted(jobId: UUID) {
        jobs.removeAll { $0.id == jobId }
        pendingCount = jobs.count
        isSyncing = !jobs.isEmpty && jobs.contains { $0.lastAttemptAt != nil }
        saveQueue()

        // Update recording history with sync timestamp
        WatchRecordingHistory.shared.markSynced(id: jobId)
    }

    func markFailed(jobId: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[idx].retryCount += 1
        jobs[idx].lastAttemptAt = Date()

        // If we've exceeded max retries, give up (prevents infinite retries for corrupt files)
        if jobs[idx].retryCount >= Self.maxRetries {
            print("WatchSyncQueue: giving up on job \(jobId) after \(Self.maxRetries) retries")
            deleteLocalFile(for: jobs[idx])
            jobs.remove(at: idx)
        }

        pendingCount = jobs.count
        isSyncing = false
        saveQueue()
    }

    func updateSyncingState(isActive: Bool) {
        isSyncing = isActive
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
        pendingCount = jobs.count
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
        pendingCount = jobs.count
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: Self.queueFileURL)
    }

    private func deleteLocalFile(for job: WatchSyncJob) {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let fileURL = documentsDir.appendingPathComponent(job.audioFileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
