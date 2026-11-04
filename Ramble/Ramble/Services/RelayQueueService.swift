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
//  delivery path, and Ramble is meant to work with the phone offline for a
//  day or more. So transient failures (offline, attestation hiccup, 5xx)
//  retry until delivered: 5s, 30s, 2m, 10m, 30m, then hourly. Only a
//  permanent error (the relay rejecting the upload itself) stops them.
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

    /// Activity log entries for retries stop after this many, so a phone
    /// that's offline for days doesn't fill the log with "retrying in 1 hour".
    static let loggedRetries = 5

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
        isProcessing || (!relay.isWaitingForUnlock && queue.contains { ($0.nextRetryAt ?? .distantPast) <= Date() })
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
        var missed: [UUID] = []
        for recording in storageService.loadRecordings() {
            guard !queue.contains(where: { $0.recordingId == recording.id }) else { continue }
            if let status = recording.relayStatus, status == .pending || status == .sending {
                queue.append(RelayJob(recordingId: recording.id))
            } else if isMissed(recording) {
                queue.append(RelayJob(recordingId: recording.id))
                missed.append(recording.id)
            }
        }
        for id in missed {
            updateRecording(id) {
                $0.relayStatus = .pending
                $0.activityLog.append(ActivityEntry("Queued for your agent (it was skipped earlier)"))
            }
        }
        // A foreground or background wake is a good moment to retry early.
        for i in queue.indices { queue[i].nextRetryAt = nil }
        saveQueue()
        processNextIfNeeded()
    }

    /// A transcribed recording made while an agent was connected that never
    /// entered the queue. Older builds skipped recordings that reached a
    /// locked phone, because the Keychain read made it look like no agent was
    /// connected. Recordings from before the first agent was paired are left
    /// alone, so connecting an agent never floods it with old thoughts.
    private func isMissed(_ recording: Recording) -> Bool {
        guard recording.relayStatus == nil,
              recording.status == .completed,
              let text = recording.transcription,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              relay.hasConnectedAgents,
              let since = relay.connectedSince else { return false }
        return recording.createdAt >= since
    }

    func processNextIfNeeded() {
        guard !isProcessing else { return }
        // Locked phone: jobs stay queued and resume on unlock (see RambleApp).
        guard !relay.isWaitingForUnlock else { return }
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
            if attempt <= RelayJob.loggedRetries + 1 {
                $0.activityLog.append(ActivityEntry(
                    attempt == 1 ? "Sending to agent…" : "Sending to agent… (attempt \(attempt))"
                ))
            }
        }

        do {
            let queued = try await relay.upload(recording: recording, transcription: text)
            guard queued > 0 else {
                // Every agent was disconnected (maybe from another screen), so
                // nothing is waiting anywhere. Don't call it sent.
                updateRecording(job.recordingId) {
                    $0.relayStatus = nil
                    $0.activityLog.append(ActivityEntry("Not sent — no agent is connected"))
                }
                removeJob(job)
                _ = try? await relay.refreshConnections()
                return
            }
            updateRecording(job.recordingId) {
                $0.relayStatus = .delivered
                $0.activityLog.append(ActivityEntry(
                    "Sent to the relay for \(queued) agent\(queued == 1 ? "" : "s")",
                    httpStatus: 200
                ))
            }
            removeJob(job)
        } catch RelayError.deviceLocked {
            // Not a failed attempt: nothing was sent. The queue holds while
            // locked and resumes on unlock, foreground or the deferred task.
            var next = job
            next.nextRetryAt = Date().addingTimeInterval(Self.lockedRetryDelay)
            updateRecording(job.recordingId) {
                $0.relayStatus = .pending
                $0.activityLog.append(ActivityEntry("Waiting for this iPhone to be unlocked"))
            }
            updateJob(next)
            BackgroundTaskService.shared.scheduleSyncTask()
        } catch let error as RelayError where error.isTransient {
            var next = job
            next.retryCount = attempt
            next.nextRetryAt = Date().addingTimeInterval(next.retryDelaySeconds)
            updateRecording(job.recordingId) {
                $0.relayStatus = .pending
                if attempt <= RelayJob.loggedRetries {
                    $0.activityLog.append(ActivityEntry(
                        "Send to agent failed — \(error.localizedDescription) Retrying in \(Self.describe(next.retryDelaySeconds))."
                            + (attempt == RelayJob.loggedRetries ? " It keeps trying every hour until it's sent." : "")
                    ))
                }
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

    private static let lockedRetryDelay: TimeInterval = 600

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
