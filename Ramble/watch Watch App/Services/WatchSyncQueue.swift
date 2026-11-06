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
    /// When WatchConnectivity last finished sending the file. The audio stays
    /// on the watch until the phone's receipt arrives; if none comes, the
    /// file is sent again (see WatchConnectivityService.receiptTimeout).
    var handedOffAt: Date?
    /// When the watch first handed the file to WatchConnectivity, and when it
    /// last did. Sent to the phone with the file so its activity log can
    /// tell a slow watch from a slow transfer. Optional so queues saved by
    /// older builds still load.
    var firstSentAt: Date?
    var lastSentAt: Date?
    var sendCount: Int?

    /// When the recording ended, i.e. when it started waiting to reach the phone.
    var savedAt: Date { createdAt.addingTimeInterval(duration) }

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(audioFileName)
    }
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

    /// The file was just handed to WatchConnectivity. Returns the updated job.
    @discardableResult
    func markSent(jobId: UUID) -> WatchSyncJob? {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return nil }
        let now = Date()
        if jobs[idx].firstSentAt == nil { jobs[idx].firstSentAt = now }
        jobs[idx].lastSentAt = now
        jobs[idx].sendCount = (jobs[idx].sendCount ?? 0) + 1
        saveQueue()
        return jobs[idx]
    }

    func markHandedOff(jobId: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[idx].handedOffAt = Date()
        saveQueue()
    }

    /// Never gives up and never deletes the audio: the watch may hold the only
    /// copy. Retries are spaced out by WatchConnectivityService.
    func markFailed(jobId: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[idx].retryCount += 1
        jobs[idx].handedOffAt = nil
        saveQueue()
    }

    /// Drop jobs whose audio file no longer exists on disk.
    func pruneOrphanedJobs() {
        let before = jobs.count
        jobs.removeAll { !FileManager.default.fileExists(atPath: $0.fileURL.path) }
        if jobs.count != before { saveQueue() }
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
