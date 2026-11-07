//
//  WatchRelayService.swift
//  watch Watch App
//
//  Sends each note straight to Ramble's relay and learns its status back:
//  PUT /notes/:id with the raw audio, GET /notes/:id until it's done, and
//  GET /account for the unlock (specs/relay-api.md).
//  The watch never gives up on a note and never deletes its audio because
//  uploads fail; it keeps the audio until the note is final and the iPhone
//  has it, or 30 days after the final state.
//

import Combine
import Foundation
import Network
import WatchKit

@MainActor
final class WatchRelayService: ObservableObject {
    static let shared = WatchRelayService()

    /// Notes with an upload running in the background session.
    @Published private(set) var uploadingIDs: Set<UUID> = []

    static let backgroundRefreshTaskID = "dev.goodloop.ramble.watch.refresh"

    private static let pollInterval: TimeInterval = 10
    private static let tickInterval: UInt64 = 5_000_000_000
    private static let backgroundInterval: TimeInterval = 15 * 60
    private static let maxBackoff: TimeInterval = 5 * 60
    private static let audioKeepAfterFinal: TimeInterval = 30 * 24 * 3600
    private static let recentKeep: TimeInterval = 24 * 3600

    private let store = WatchNoteStore.shared
    private let connection = WatchConnection.shared
    private let api: URLSession
    private let pathMonitor = NWPathMonitor()
    private var wasOnline: Bool?
    private var adopted = false
    private var foregroundLoop: Task<Void, Never>?
    private var backgroundRefreshDate: Date?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        api = URLSession(configuration: configuration)

        // Reconnect to the background session so results of uploads that
        // finished while the app wasn't running are delivered.
        _ = RelayUploadSession.shared

        pathMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                WatchRelayService.shared.networkChanged(online: online)
            }
        }
        pathMonitor.start(queue: .main)
    }

    // MARK: - Entry points

    /// Right after a stop, while the app is still in front, so the
    /// background transfer is started before the wrist drops.
    func noteSaved(_ note: WatchNoteRecord) {
        if connection.isConnected {
            startUpload(note)
        }
        scheduleBackgroundRefresh()
    }

    /// The app came to the foreground.
    func appBecameActive() {
        startForegroundLoop()
        Task { await openPass() }
    }

    func appLeftForeground() {
        foregroundLoop?.cancel()
        foregroundLoop = nil
        scheduleBackgroundRefresh()
    }

    /// Everything the watch does each time the app opens.
    func openPass() async {
        cleanUp()
        if !connection.isConnected {
            WatchConnectivityService.shared.sendNeedsConnection(replaces: connection.tokenToReplace)
        }
        await retryPass(force: true)
        await refreshAccount()
        await pollPass(includeFailed: true, force: true)
        WatchConnectivityService.shared.resendUnconfirmedAudio()
        cleanUp()
        scheduleBackgroundRefresh()
    }

    /// A background refresh. Best effort: watchOS decides when it runs.
    func backgroundPass() async {
        backgroundRefreshDate = nil
        cleanUp()
        await retryPass(force: true)
        await pollPass(includeFailed: false, force: true)
        if store.notes.contains(where: { $0.upload == .heldUnlock }) {
            await refreshAccount()
        }
        cleanUp()
        scheduleBackgroundRefresh()
    }

    /// The iPhone connected the watch (a new token; the old one is revoked).
    /// The new token uploads what's waiting and reads the inbox's watch notes.
    func connectionReplaced() {
        releaseHolds([.heldUnlock])
        Task { await retryPass(force: true) }
    }

    /// The iPhone or the server says Ramble is unlocked.
    func accountUnlocked() {
        releaseHolds([.heldUnlock])
        Task { await retryPass(force: true) }
    }

    /// The person saw these notes in Recent.
    func markSeen(_ ids: [UUID]) {
        let now = Date()
        for id in ids {
            store.update(id) { note in
                if note.firstSeenAt == nil { note.firstSeenAt = now }
            }
        }
    }

    // MARK: - Network changes

    private func networkChanged(online: Bool) {
        let cameBack = online && wasOnline == false
        wasOnline = online
        if cameBack {
            Task { await retryPass(force: true) }
        }
    }

    // MARK: - Uploads

    func retryPass(force: Bool) async {
        await adoptRunningUploads()
        guard connection.isConnected else { return }
        let now = Date()
        let due = store.notes
            .filter { note in
                guard note.upload == .waiting, !note.audioDeleted, !uploadingIDs.contains(note.id) else { return false }
                if !force, let next = note.nextAttemptAt, next > now { return false }
                return true
            }
            .sorted { $0.recordedAt < $1.recordedAt } // Oldest first
        for note in due {
            startUpload(note)
        }
    }

    /// Uploads started before a relaunch are still owned by the system.
    /// Track them instead of starting duplicates.
    private func adoptRunningUploads() async {
        guard !adopted else { return }
        let running = await RelayUploadSession.shared.runningNoteIDs()
        adopted = true
        uploadingIDs.formUnion(running)
    }

    private func startUpload(_ note: WatchNoteRecord) {
        guard let token = connection.token, !connection.tokenRejected, !uploadingIDs.contains(note.id)
        else { return }
        guard FileManager.default.fileExists(atPath: note.fileURL.path) else {
            markLost(note.id)
            return
        }
        var request = URLRequest(url: noteURL(note.id))
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue(note.recordedAtText, forHTTPHeaderField: "X-Ramble-Recorded-At")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        RelayUploadSession.shared.upload(request, fromFile: note.fileURL, noteID: note.id)
        uploadingIDs.insert(note.id)
    }

    /// One answer to PUT /notes/:id, handled per relay-api.md.
    func handleUpload(_ outcome: RelayUploadOutcome) {
        uploadingIDs.remove(outcome.noteID)
        guard let before = store.note(outcome.noteID) else { return }
        let id = before.id
        let now = Date()

        guard let status = outcome.status else {
            // Offline, timed out, or the connection dropped
            backOff(id, now: now)
            finishChange(before: before)
            return
        }

        let reason = Self.reason(in: outcome.body)
        switch status {
        case 200, 201:
            if let body = try? JSONDecoder().decode(RelayNoteBody.self, from: outcome.body) {
                applyNote(body, to: id, now: now)
            } else {
                store.update(id) { note in
                    note.upload = .accepted
                    note.status = note.status ?? .transcribing
                    note.failureCount = 0
                    note.nextAttemptAt = nil
                }
            }
        case 402 where reason == "free_notes_used":
            store.update(id) { note in
                note.upload = .heldUnlock
                note.nextAttemptAt = nil
                note.failureCount = 0
            }
        case 413:
            refuse(id, as: .refusedTooLong, now: now)
        case 415:
            refuse(id, as: .refusedBadUpload, now: now)
        case 400 where reason == "bad_upload", 403 where reason == "suspended":
            refuse(id, as: .refusedBadUpload, now: now)
        case 401:
            // Replaced or revoked. The note stays waiting for a new token.
            let wasConnected = connection.isConnected
            connection.markRejected(token: outcome.token)
            if wasConnected && !connection.isConnected {
                WatchConnectivityService.shared.sendNeedsConnection(replaces: connection.tokenToReplace)
            }
            if outcome.token != connection.token, connection.isConnected {
                // An older token's answer; upload again with the current one.
                Task { await retryPass(force: true) }
            }
        case 429:
            store.update(id) { $0.nextAttemptAt = now.addingTimeInterval(outcome.retryAfter ?? 60) }
        default:
            // 5xx, 503 unavailable, 408, 411, anything unexpected
            backOff(id, now: now)
        }
        finishChange(before: before)
    }

    private func refuse(_ id: UUID, as state: WatchUploadState, now: Date) {
        store.update(id) { note in
            note.upload = state
            note.finalAt = now
            note.nextAttemptAt = nil
        }
    }

    private func backOff(_ id: UUID, now: Date) {
        store.update(id) { note in
            note.failureCount += 1
            let delay = min(10 * pow(2.0, Double(max(0, note.failureCount - 1))), Self.maxBackoff)
            note.nextAttemptAt = now.addingTimeInterval(delay)
        }
    }

    private func markLost(_ id: UUID) {
        let now = Date()
        guard let before = store.note(id) else { return }
        store.update(id) { note in
            note.upload = .lost
            note.finalAt = now
            note.audioDeleted = true
        }
        finishChange(before: before)
    }

    /// Tells the iPhone when a hold starts or ends, and refreshes alerts.
    private func finishChange(before: WatchNoteRecord) {
        if let after = store.note(before.id), after.holdValue != before.holdValue {
            WatchConnectivityService.shared.sendNoteDetails(after)
        }
        scheduleBackgroundRefresh()
    }

    // MARK: - Holds

    private func releaseHolds(_ kinds: Set<WatchUploadState>) {
        let now = Date()
        // Oldest first, so the iPhone hears about them in order
        for note in store.notes.reversed() where kinds.contains(note.upload) {
            let change = store.update(note.id) { record in
                record.upload = .waiting
                record.waitingSince = now // The 6 hours count from the release
                record.nextAttemptAt = nil
                record.failureCount = 0
            }
            if let after = change?.after {
                WatchConnectivityService.shared.sendNoteDetails(after)
            }
        }
    }

    // MARK: - Status and transcript

    /// Reads accepted notes that aren't done. `force` ignores the 10 s
    /// spacing; `includeFailed` also rereads failed notes still in Recent,
    /// since a retry from the iPhone can change them.
    func pollPass(includeFailed: Bool, force: Bool) async {
        let now = Date()
        let targets = store.notes.filter { note in
            if note.needsPolling {
                guard !force, let last = note.lastPolledAt else { return true }
                return now.timeIntervalSince(last) >= Self.pollInterval - 0.5
            }
            return includeFailed && note.upload == .accepted && note.status == .failed && !note.hiddenFromRecent
        }
        for note in targets {
            await poll(note)
        }
    }

    private func poll(_ note: WatchNoteRecord) async {
        guard let token = connection.token, !connection.tokenRejected else { return }
        var request = URLRequest(url: noteURL(note.id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        store.update(note.id) { $0.lastPolledAt = Date() }

        guard let result = try? await api.data(for: request),
              let http = result.1 as? HTTPURLResponse
        else { return }
        let now = Date()
        switch http.statusCode {
        case 200:
            guard let body = try? JSONDecoder().decode(RelayNoteBody.self, from: result.0),
                  let before = store.note(note.id)
            else { return }
            applyNote(body, to: note.id, now: now)
            finishChange(before: before)
        case 401:
            // This token was replaced or revoked. The note is read again
            // once the iPhone connects the watch.
            let wasConnected = connection.isConnected
            connection.markRejected(token: token)
            if wasConnected && !connection.isConnected {
                WatchConnectivityService.shared.sendNeedsConnection(replaces: connection.tokenToReplace)
            }
        case 404:
            // The current connection can't read the note (the iPhone set up
            // Ramble again as a new inbox, or the note expired). Stop asking.
            guard note.needsPolling, let before = store.note(note.id) else { return }
            store.update(note.id) { record in
                record.status = .done
                record.result = nil
                record.preview = nil
                if record.doneAt == nil { record.doneAt = now }
                if record.finalAt == nil { record.finalAt = now }
            }
            finishChange(before: before)
        default:
            break
        }
    }

    private func applyNote(_ body: RelayNoteBody, to id: UUID, now: Date) {
        let status = WatchServerStatus(rawValue: body.status) ?? .transcribing
        store.update(id) { note in
            note.upload = .accepted
            note.failureCount = 0
            note.nextAttemptAt = nil
            note.lastPolledAt = now
            note.status = status
            note.result = body.result
            switch status {
            case .done:
                if let transcript = body.transcript {
                    note.preview = WatchFormat.firstLine(transcript)
                }
                if note.doneAt == nil { note.doneAt = now }
                if note.finalAt == nil { note.finalAt = now }
            case .failed:
                note.doneAt = nil
                if note.finalAt == nil { note.finalAt = now }
            case .transcribing:
                // A retry from the iPhone started it again
                note.doneAt = nil
                note.finalAt = nil
            }
        }
    }

    // MARK: - Account

    func refreshAccount() async {
        guard let token = connection.token, !connection.tokenRejected else { return }
        var request = URLRequest(url: connection.baseURL.appendingPathComponent("account"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let result = try? await api.data(for: request),
              let http = result.1 as? HTTPURLResponse
        else { return }

        switch http.statusCode {
        case 200:
            guard let account = try? JSONDecoder().decode(RelayAccountBody.self, from: result.0) else { return }
            connection.setUnlocked(account.unlocked)
            if account.unlocked, store.notes.contains(where: { $0.upload == .heldUnlock }) {
                accountUnlocked()
            }
        case 401:
            let wasConnected = connection.isConnected
            connection.markRejected(token: token)
            if wasConnected && !connection.isConnected {
                WatchConnectivityService.shared.sendNeedsConnection(replaces: connection.tokenToReplace)
            }
        default:
            break
        }
    }

    // MARK: - Keeping and deleting

    /// Lost-audio checks, audio deletion, and notes leaving Recent.
    func cleanUp(now: Date = Date()) {
        for original in store.notes {
            let id = original.id

            // The audio went missing before the server accepted it
            if original.isUnaccepted, !uploadingIDs.contains(id),
               !FileManager.default.fileExists(atPath: original.fileURL.path) {
                store.update(id) { note in
                    note.upload = .lost
                    note.finalAt = now
                    note.audioDeleted = true
                }
                continue
            }

            // Keep audio until final and on the iPhone, or 30 days after final
            if !original.audioDeleted, original.isFinal {
                let finalAt = original.finalAt ?? now
                if original.finalAt == nil { store.update(id) { $0.finalAt = now } }
                if original.phoneHasAudio || now.timeIntervalSince(finalAt) >= Self.audioKeepAfterFinal {
                    WatchConnectivityService.shared.cancelAudioTransfers(for: id)
                    try? FileManager.default.removeItem(at: original.fileURL)
                    store.update(id) { $0.audioDeleted = true }
                }
            }

            // Leave Recent 24 hours after the transcript, or after first seen
            guard let note = store.note(id), !note.hiddenFromRecent else { continue }
            let display = WatchNoteDisplay.resolve(note, isUploading: false, stuckAfter: .infinity, now: now)
            let leaveFrom: Date?
            switch display {
            case .done, .silent:
                leaveFrom = note.doneAt
            default:
                leaveFrom = display.isFinalProblem ? note.firstSeenAt : nil
            }
            if let leaveFrom, now.timeIntervalSince(leaveFrom) >= Self.recentKeep {
                store.update(id) { $0.hiddenFromRecent = true }
            }
        }

        // Past 50, drop only done, failed, refused or lost notes, oldest first
        let recent = store.recent
        if recent.count > WatchNoteStore.maxRecent {
            let extra = recent.count - WatchNoteStore.maxRecent
            let droppable = recent.filter(\.isFinal).sorted { $0.recordedAt < $1.recordedAt }.prefix(extra)
            for note in droppable {
                store.update(note.id) { $0.hiddenFromRecent = true }
            }
        }

        // A note is forgotten once it has left Recent and its audio is gone
        let gone = Set(store.notes.filter { $0.hiddenFromRecent && $0.audioDeleted }.map(\.id))
        store.remove(gone)
    }

    // MARK: - Background refresh

    /// Asks watchOS for a background pass: every 15 minutes while there is
    /// work, or by `deadline` when given.
    /// watchOS keeps one request, so an earlier one replaces a later one.
    func scheduleBackgroundRefresh(before deadline: Date? = nil) {
        let now = Date()
        let hasWork = store.notes.contains {
            $0.upload == .waiting || $0.needsPolling
        }
        guard hasWork || deadline != nil else { return }
        var date = now.addingTimeInterval(Self.backgroundInterval)
        if let deadline {
            date = min(date, max(deadline, now.addingTimeInterval(60)))
        }
        if let backgroundRefreshDate, backgroundRefreshDate > now, backgroundRefreshDate <= date { return }
        backgroundRefreshDate = date
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: date,
            userInfo: Self.backgroundRefreshTaskID as NSString,
            scheduledCompletion: Self.scheduleCompletion()
        )
    }

    /// Made off the main actor: watchOS may call it on any queue.
    private nonisolated static func scheduleCompletion() -> @Sendable (Error?) -> Void {
        { error in
            if let error { print("Couldn't schedule watch background refresh: \(error)") }
        }
    }

    // MARK: - Foreground loop

    /// While the app is open: backoff retries when due, and a status read
    /// every 10 seconds for notes being transcribed.
    private func startForegroundLoop() {
        guard foregroundLoop == nil else { return }
        foregroundLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickInterval)
                guard !Task.isCancelled, let self else { return }
                await self.retryPass(force: false)
                await self.pollPass(includeFailed: false, force: false)
                self.cleanUp()
            }
        }
    }

    // MARK: - Helpers

    private func noteURL(_ id: UUID) -> URL {
        connection.baseURL
            .appendingPathComponent("notes")
            .appendingPathComponent(id.uuidString.uppercased())
    }

    private static func reason(in body: Data) -> String? {
        (try? JSONDecoder().decode(RelayErrorBody.self, from: body))?.reason
    }
}

// MARK: - Wire shapes (relay-api.md)

struct RelayNoteBody: Decodable {
    let id: String?
    let status: String
    let result: String?
    let transcript: String?
    let transcriptCleared: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case result
        case transcript
        case transcriptCleared = "transcript_cleared"
    }
}

struct RelayErrorBody: Decodable {
    let error: String?
    let reason: String?
}

struct RelayAccountBody: Decodable {
    let unlocked: Bool
}
