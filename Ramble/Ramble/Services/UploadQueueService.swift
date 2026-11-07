//
//  UploadQueueService.swift
//  Ramble
//
//  Sends this phone's notes to Ramble's server with PUT /notes/{id}
//  (specs/relay-api.md "Notes", specs/phone.md "Phone notes upload on their
//  own"), and the person's hand retries of failed notes. Watch notes upload
//  from the watch; the phone only re-sends one when the person retries it.
//
//  The queue is the recordings themselves: a phone note that isn't accepted
//  and isn't held, or any note with a retry requested. Only the backoff
//  lives here.
//

import Combine
import Foundation

@MainActor
final class UploadQueueService: ObservableObject {
    static let shared = UploadQueueService()

    @Published private(set) var isProcessing = false

    private struct Backoff: Codable {
        var attempts: Int
        var nextAt: Date
    }

    private let storage = StorageService.shared
    private let relay = RelayService.shared
    private var backoff: [UUID: Backoff] = [:]
    private var wakeTask: Task<Void, Never>?
    private let backoffFile = StorageService.documentsDirectory.appendingPathComponent("upload_backoff.json")

    private init() {
        if let data = try? Data(contentsOf: backoffFile),
           let stored = try? JSONDecoder().decode([UUID: Backoff].self, from: data) {
            backoff = stored
        }
    }

    var hasActiveWork: Bool {
        isProcessing || (canRun && nextRunnable(now: Date()) != nil)
    }

    private var canRun: Bool {
        Consent.hasConsented && !KeychainService.isLocked
    }

    // MARK: - Public API

    /// A phone note was just saved.
    func enqueue(recordingId: UUID) {
        processNextIfNeeded()
    }

    /// Ramble opened or woke: try everything now. Unlock holds wait for the
    /// unlock.
    func resume(appOpened: Bool = false) {
        if appOpened {
            backoff = [:]
            saveBackoff()
        }
        processNextIfNeeded()
    }

    /// The inbox is unlocked or has free notes again.
    func releaseUnlockHolds() {
        releaseHolds { $0 == .unlock }
        processNextIfNeeded()
    }

    /// "Retry" on a note that couldn't transcribe. The audio must be on this
    /// phone; a watch note fetches it first (see the note screen).
    func retry(recordingId: UUID) {
        storage.update(recordingId) {
            guard $0.canRetryTranscription else { return }
            $0.retryRequested = true
            $0.activityLog.append(ActivityEntry("Retry requested"))
        }
        backoff[recordingId] = nil
        saveBackoff()
        processNextIfNeeded()
    }

    func processNextIfNeeded() {
        guard !isProcessing, canRun else { return }
        guard let recording = nextRunnable(now: Date()) else {
            scheduleWake()
            return
        }
        isProcessing = true
        Task { await process(recording) }
    }

    // MARK: - Selection

    private func needsUpload(_ recording: Recording, now: Date) -> Bool {
        if recording.retryRequested {
            return recording.hold == nil && recording.hasAudio
        }
        guard recording.source == .phone, recording.status == .recorded else { return false }
        switch recording.hold {
        case nil: return recording.hasAudio
        case .unlock, .tooLong, .couldntSend: return false
        }
    }

    /// Oldest first, so held notes go out in the order they were said.
    private func nextRunnable(now: Date) -> Recording? {
        storage.loadRecordings()
            .filter { needsUpload($0, now: now) && (backoff[$0.id]?.nextAt ?? .distantPast) <= now }
            .min { $0.createdAt < $1.createdAt }
    }

    private func releaseHolds(_ matches: (NoteHold) -> Bool) {
        let now = Date()
        var recordings = storage.loadRecordings()
        var changed = false
        for i in recordings.indices {
            guard let hold = recordings[i].hold, matches(hold),
                  recordings[i].source == .phone || recordings[i].retryRequested else { continue }
            recordings[i].hold = nil
            recordings[i].releasedAt = now
            changed = true
        }
        if changed { storage.saveRecordings(recordings) }
    }

    // MARK: - Processing

    private func process(_ recording: Recording) async {
        defer {
            isProcessing = false
            processNextIfNeeded()
        }
        let id = recording.id
        let isRetry = recording.retryRequested

        let response: RelayService.UploadResponse
        do {
            response = try await relay.uploadNote(recording, isRetry: isRetry)
        } catch let error as RelayError {
            switch error {
            case .deviceLocked, .notConsented:
                // Nothing was sent; resumes on unlock or the next open.
                return
            default:
                failTransiently(id, message: error.localizedDescription)
                return
            }
        } catch {
            failTransiently(id, message: RelayService.describe(error))
            return
        }

        handle(response, for: id, isRetry: isRetry)
    }

    private func handle(_ response: RelayService.UploadResponse, for id: UUID, isRetry: Bool) {
        let status = response.status
        switch status {
        case 200, 201:
            clearBackoff(id)
            storage.update(id) {
                $0.hold = nil
                $0.lastError = nil
                if isRetry {
                    $0.retryRequested = false
                    if status == 201 {
                        $0.retryCount += 1
                        $0.failureResult = nil
                        $0.agentDelivery = nil
                    }
                }
                $0.activityLog.append(ActivityEntry(
                    status == 201 ? (isRetry ? "Retry accepted by Ramble's server" : "Accepted by Ramble's server")
                        : "Ramble's server already had it",
                    httpStatus: status
                ))
            }
            if let note = response.note {
                NoteSyncService.shared.apply(note, forceStatus: isRetry && status == 201)
            } else {
                storage.update(id) { if $0.status == .recorded || $0.status == .failed { $0.status = .transcribing } }
            }

        case 402:
            clearBackoff(id)
            storage.update(id) {
                $0.hold = .unlock
                $0.activityLog.append(ActivityEntry("Held until Ramble is unlocked", httpStatus: 402))
            }
            AccountService.shared.noteFreeNotesUsed()

        case 413:
            refuseForGood(id, as: .tooLong, response)

        case 415:
            refuseForGood(id, as: .couldntSend, response)

        case 403 where response.reason == "suspended":
            // Uploads from this setup were paused by hand: a plain refusal.
            refuseForGood(id, as: .couldntSend, response)

        case 400 where response.reason == "recorded_in_future":
            // The recorded time is ahead of the server's clock; it passes.
            failTransiently(id, message: response.message ?? "Recorded time is in the future.", status: status, atLeast: 300)

        case 400:
            refuseForGood(id, as: .couldntSend, response)

        case 409 where response.reason == "retry_limit":
            clearBackoff(id)
            storage.update(id) {
                $0.retryRequested = false
                $0.retryCount = Recording.maxRetries
                $0.activityLog.append(ActivityEntry("Retry refused: no retries left", httpStatus: 409))
            }

        case 429:
            failTransiently(id, message: "Too many uploads right now.", status: status, atLeast: response.retryAfter ?? 60)

        case 401:
            // The relay forgot this inbox; the next attempt sets up again.
            failTransiently(id, message: "Ramble's server didn't recognize this phone.", status: status)

        default:
            failTransiently(id, message: response.message ?? "Ramble's server returned an error (\(status)).", status: status)
        }
    }

    private func refuseForGood(_ id: UUID, as hold: NoteHold, _ response: RelayService.UploadResponse) {
        clearBackoff(id)
        storage.update(id) {
            $0.hold = hold
            $0.retryRequested = false
            $0.lastError = response.message
            $0.activityLog.append(ActivityEntry(
                "Refused by Ramble's server — \(response.reason ?? response.message ?? "unreadable audio")",
                httpStatus: response.status
            ))
        }
    }

    /// 10 seconds, doubling to every 5 minutes, until accepted.
    private func failTransiently(_ id: UUID, message: String, status: Int? = nil, atLeast minimum: TimeInterval = 0) {
        var entry = backoff[id] ?? Backoff(attempts: 0, nextAt: Date())
        entry.attempts += 1
        let delay = max(minimum, min(10 * pow(2, Double(entry.attempts - 1)), 300))
        entry.nextAt = Date().addingTimeInterval(delay)
        backoff[id] = entry
        saveBackoff()
        let logIt = entry.attempts <= 5
        storage.update(id) {
            $0.lastError = message
            if logIt {
                $0.activityLog.append(ActivityEntry("Upload failed — \(message)", httpStatus: status))
            }
        }
        BackgroundTaskService.shared.scheduleSyncTask()
    }

    private func clearBackoff(_ id: UUID) {
        guard backoff[id] != nil else { return }
        backoff[id] = nil
        saveBackoff()
    }

    /// Re-run when the earliest backoff ends, while alive.
    private func scheduleWake() {
        wakeTask?.cancel()
        let now = Date()
        guard let next = backoff.values.map(\.nextAt).filter({ $0 > now }).min() else { return }
        let delay = max(1, next.timeIntervalSince(now))
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(delay, 86_400) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.processNextIfNeeded()
        }
    }

    private func saveBackoff() {
        guard let data = try? JSONEncoder().encode(backoff) else { return }
        try? data.write(to: backoffFile)
    }
}
