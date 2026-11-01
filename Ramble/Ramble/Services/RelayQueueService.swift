//
//  RelayQueueService.swift
//  Ramble
//
//  Persistent upload queue for the Ramble Relay. Independent of the webhook
//  queue: a recording can go to a webhook, the relay, or both, and a failure
//  in one never holds up the other.
//
//  Retries are more patient than webhooks. A webhook is the user's own
//  endpoint and three tries tells them it's broken; the relay is the core
//  delivery path, so transient failures (offline, attestation hiccup, 5xx)
//  keep retrying with backoff for about a day before giving up.
//

import Combine
import Foundation

struct RelayJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    var retryCount: Int
    let createdAt: Date
    var nextRetryAt: Date?

    init(recordingId: UUID) {
        self.id = UUID()
        self.recordingId = recordingId
        self.retryCount = 0
        self.createdAt = Date()
        self.nextRetryAt = nil
    }

    static let maxRetries = 12

    /// 5s, 30s, 2m, 10m, 30m, then hourly.
    var retryDelaySeconds: TimeInterval {
        let schedule: [TimeInterval] = [5, 30, 120, 600, 1800]
        return retryCount < schedule.count ? schedule[retryCount] : 3600
    }
}

@MainActor
final class RelayQueueService: ObservableObject {
    static let shared = RelayQueueService()

    @Published private(set) var isProcessing = false

    var hasActiveWork: Bool {
        isProcessing || queue.contains { ($0.nextRetryAt ?? .distantPast) <= Date() }
    }

    private let storageService = StorageService.shared
    private let relay = RelayService.shared
    private var queue: [RelayJob] = []
    private var wakeTask: Task<Void, Never>?
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("relay_queue.json")

    private init() {
        loadQueue()
    }

    // MARK: - Public API

    /// Queue a transcribed recording for the relay, if any agent is connected.
    func enqueue(recordingId: UUID) {
        guard relay.hasConnectedAgents else { return }
        guard !queue.contains(where: { $0.recordingId == recordingId }) else { return }

        updateRecording(recordingId) { $0.relayStatus = .pending }
        queue.append(RelayJob(recordingId: recordingId))
        saveQueue()
        processNextIfNeeded()
    }

    /// User-initiated resend from the recording detail screen.
    func resend(recordingId: UUID) {
        guard relay.hasConnectedAgents else { return }
        updateRecording(recordingId) {
            $0.relayStatus = .pending
            $0.activityLog.append(ActivityEntry("Manual send to agent requested"))
        }
        queue.removeAll { $0.recordingId == recordingId }
        queue.append(RelayJob(recordingId: recordingId))
        saveQueue()
        processNextIfNeeded()
    }

    func resumePendingJobs() {
        for recording in storageService.loadRecordings() {
            if let status = recording.relayStatus, status == .pending || status == .sending,
               !queue.contains(where: { $0.recordingId == recording.id }) {
                queue.append(RelayJob(recordingId: recording.id))
            }
        }
        // A foreground or background wake is a good moment to retry early.
        for i in queue.indices { queue[i].nextRetryAt = nil }
        saveQueue()
        processNextIfNeeded()
    }

    func processNextIfNeeded() {
        guard !isProcessing else { return }
        let now = Date()
        guard let job = queue.first(where: { ($0.nextRetryAt ?? .distantPast) <= now }) else {
            scheduleWake()
            return
        }
        isProcessing = true
        Task { await process(job) }
    }

    // MARK: - Processing

    private func process(_ job: RelayJob) async {
        defer {
            isProcessing = false
            processNextIfNeeded()
        }

        guard let recording = storageService.loadRecordings().first(where: { $0.id == job.recordingId }),
              let text = recording.transcription,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            removeJob(job)
            return
        }

        let attempt = job.retryCount + 1
        updateRecording(job.recordingId) {
            $0.relayStatus = .sending
            $0.activityLog.append(ActivityEntry(
                attempt == 1 ? "Sending to agent…" : "Sending to agent… (attempt \(attempt))"
            ))
        }

        do {
            let queued = try await relay.upload(recording: recording, transcription: text)
            updateRecording(job.recordingId) {
                $0.relayStatus = .delivered
                $0.activityLog.append(ActivityEntry(
                    queued == 1
                        ? "Waiting on the relay for 1 agent"
                        : "Waiting on the relay for \(queued) agents",
                    httpStatus: 200
                ))
            }
            removeJob(job)
        } catch let error as RelayError where error.isTransient && attempt < RelayJob.maxRetries {
            var next = job
            next.retryCount = attempt
            next.nextRetryAt = Date().addingTimeInterval(next.retryDelaySeconds)
            updateRecording(job.recordingId) {
                $0.relayStatus = .pending
                $0.activityLog.append(ActivityEntry(
                    "Send to agent failed — \(error.localizedDescription) Retrying in \(Self.describe(next.retryDelaySeconds))."
                ))
            }
            updateJob(next)
        } catch {
            updateRecording(job.recordingId) {
                $0.relayStatus = .failed
                $0.activityLog.append(ActivityEntry("Send to agent failed — \(error.localizedDescription)"))
            }
            removeJob(job)
        }
    }

    /// Re-run the queue when the earliest backoff ends, while the app is alive.
    /// Persisted jobs also resume on the next foreground or background wake.
    private func scheduleWake() {
        wakeTask?.cancel()
        guard let next = queue.compactMap(\.nextRetryAt).min() else { return }
        let delay = max(1, next.timeIntervalSinceNow)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.processNextIfNeeded()
        }
    }

    private static func describe(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds))s" : seconds < 3600 ? "\(Int(seconds / 60)) min" : "1 hour"
    }

    // MARK: - Persistence

    private func updateRecording(_ id: UUID, _ change: (inout Recording) -> Void) {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[idx])
        storageService.saveRecordings(recordings)
    }

    private func removeJob(_ job: RelayJob) {
        queue.removeAll { $0.id == job.id }
        saveQueue()
    }

    private func updateJob(_ job: RelayJob) {
        if let index = queue.firstIndex(where: { $0.id == job.id }) {
            queue[index] = job
            saveQueue()
        }
    }

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueFile),
              let jobs = try? JSONDecoder().decode([RelayJob].self, from: data) else { return }
        queue = jobs
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}
