//
//  NoteSyncService.swift
//  Ramble
//
//  The phone's check-in with Ramble's server (specs/phone.md "When the
//  phone checks in"): pull waiting transcripts and ack each once saved,
//  refresh the delivery state of notes with agent copies waiting, and read
//  the account. Runs when Ramble opens or returns to the foreground, on
//  background refresh, and when a message from the watch wakes it.
//
//  Server notes merge into history by note ID with whatever the watch sent,
//  so a note never appears twice, and a note the person deleted never
//  comes back.
//

import Combine
import Foundation
import UIKit

@MainActor
final class NoteSyncService: ObservableObject {
    static let shared = NoteSyncService()

    @Published private(set) var isSyncing = false
    private var syncAgain = false
    private var pollTask: Task<Void, Never>?

    private let storage = StorageService.shared
    private let relay = RelayService.shared

    /// Delivery state is asked for only while the relay can still know it.
    private static let deliveryWindow: TimeInterval = 30 * 24 * 3600

    private init() {}

    var hasActiveWork: Bool { isSyncing }

    // MARK: - Check-in

    func checkIn() async {
        guard Consent.hasConsented, !KeychainService.isLocked else { return }
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            syncAgain = false
            await relay.setUpIfNeeded()
            guard relay.hasInbox else { return }
            await pushTranscriptionSettingsIfNeeded()
            await pullNotes()
            _ = try? await relay.refreshConnections()
            await refreshDelivery()
            await AccountService.shared.refresh()
        } while syncAgain
        DeliveryMonitor.shared.evaluateSoon()
    }

    /// While Ramble is on screen and a note is transcribing, check every 10
    /// seconds so the transcript shows soon after it's ready.
    func startForegroundPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard UIApplication.shared.applicationState == .active else { continue }
                let transcribing = self.storage.loadRecordings().contains { $0.status == .transcribing && $0.hold == nil }
                if transcribing { await self.checkIn() }
            }
        }
    }

    func stopForegroundPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Transcripts

    private func pullNotes() async {
        var cursor: String?
        var toAck: [UUID] = []
        repeat {
            guard let page = try? await relay.listNotes(after: cursor) else { break }
            for note in page.notes {
                let saved = apply(note)
                if saved, note.status == "done" || note.status == "failed", let id = note.uuid {
                    toAck.append(id)
                }
            }
            cursor = page.next
        } while cursor != nil
        _ = try? await relay.ackNotes(toAck)
    }

    /// Merges one server note into history. Returns true once the phone has
    /// it saved (or the person deleted it), so it can be acked.
    @discardableResult
    func apply(_ note: RelayNote, forceStatus: Bool = false) -> Bool {
        guard let id = note.uuid else { return false }
        if storage.isDeleted(id) { return true }

        var recordings = storage.loadRecordings()
        let now = Date()
        if !recordings.contains(where: { $0.id == id }) {
            let createdAt = RelayService.parseDate(note.recordedAt) ?? note.receivedAt ?? now
            let source: NoteSource = note.source == "watch" ? .watch : .phone
            var fresh = Recording(id: id, createdAt: createdAt, duration: note.duration ?? 0, source: source)
            if source == .watch {
                fresh.activityLog.append(ActivityEntry("Recorded on Apple Watch", at: createdAt))
            }
            recordings.insert(fresh, at: 0)
        }
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return false }

        var r = recordings[index]
        let hadSpeech = r.hasSpeechTranscript
        let oldStatus = r.status

        switch note.status {
        case "transcribing":
            if r.status != .completed || forceStatus { r.status = .transcribing }
        case "done":
            r.status = .completed
            // Null once the server's copy is gone; keep what the phone saved.
            if let text = note.transcript {
                r.transcription = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            r.noSpeech = note.result == "no_speech"
            r.failureResult = nil
            if r.finishedAt == nil { r.finishedAt = now }
        case "failed":
            if r.status != .completed {
                r.status = .failed
                r.failureResult = note.result
                if oldStatus != .failed { r.finishedAt = now }
            }
        default:
            break
        }
        // Accepted, so any hold from before is over (a hold on a retry
        // belongs to that retry and stays).
        if !r.retryRequested {
            r.hold = nil
        }
        if let accepted = note.receivedAt { r.acceptedAt = accepted }
        if let measured = note.duration, measured > 0 { r.duration = measured }

        if r.status != oldStatus {
            switch r.status {
            case .transcribing: r.activityLog.append(ActivityEntry("Transcribing on Ramble's server"))
            case .completed:
                r.activityLog.append(ActivityEntry(r.noSpeech ? "No speech detected" : "Transcript received"))
            case .failed:
                r.activityLog.append(ActivityEntry(note.result == "retries_exhausted"
                    ? "Transcription failed — no transcription service answered in time"
                    : "Transcription failed — the audio couldn't be turned into text"))
            case .recorded: break
            }
        }

        let gotSpeech = !hadSpeech && r.hasSpeechTranscript
        if gotSpeech { r.agentDelivery = nil }
        recordings[index] = r
        storage.saveRecordings(recordings)

        let saved = storage.recording(withId: id) != nil
        if saved && gotSpeech && SettingsService.shared.load().isWebhookConfigured {
            WebhookQueueService.shared.enqueue(recordingId: id)
        }
        return saved
    }

    // MARK: - Delivery

    private func refreshDelivery() async {
        let cutoff = Date().addingTimeInterval(-Self.deliveryWindow)
        let candidates = storage.loadRecordings().filter {
            $0.hasSpeechTranscript
                && $0.waitingSince > cutoff
                && ($0.agentDelivery == nil || ($0.agentDelivery?.waiting ?? 0) > 0)
        }
        guard !candidates.isEmpty,
              let statuses = try? await relay.deliveryStatus(for: candidates.map(\.id)),
              !statuses.isEmpty else { return }

        var recordings = storage.loadRecordings()
        var changed = false
        for i in recordings.indices {
            guard let item = statuses[recordings[i].id] else { continue }
            let next = AgentDelivery(
                copies: item.copies,
                waiting: item.waiting,
                pickedUp: item.pickedUp,
                removed: item.removed,
                firstPickedUpAt: item.firstPickedUpAt
            )
            guard next != recordings[i].agentDelivery else { continue }
            let before = recordings[i].agentDelivery
            if next.waiting == 0, next.pickedUp > 0, (before?.pickedUp ?? 0) == 0 {
                recordings[i].activityLog.append(ActivityEntry("Picked up by your agent", at: next.firstPickedUpAt ?? Date()))
            } else if next.copies > 0, next.waiting == 0, next.pickedUp == 0, (before?.removed ?? 0) == 0 {
                recordings[i].activityLog.append(ActivityEntry("Removed before your agent picked it up"))
            }
            recordings[i].agentDelivery = next
            changed = true
        }
        if changed { storage.saveRecordings(recordings) }
    }

    // MARK: - Transcription settings

    /// A change that couldn't reach the server goes up on the next check-in.
    func pushTranscriptionSettingsIfNeeded() async {
        let service = SettingsService.shared
        guard service.transcriptionSettingsDirty else { return }
        let settings = service.load()
        let body = RelayTranscriptionSettings(
            language: settings.transcriptionLanguage.code,
            removeFillerWords: settings.removeFillerWords,
            vocabulary: settings.customVocabulary
        )
        do {
            try await relay.saveTranscriptionSettings(body)
            service.transcriptionSettingsDirty = false
        } catch let error as RelayError where error.status == 400 {
            // The server won't take it; stop resending.
            service.transcriptionSettingsDirty = false
        } catch {
            // Try again next check-in.
        }
    }

    /// The server's copy, for Settings. Local edits not yet sent win.
    func pullTranscriptionSettings() async {
        let service = SettingsService.shared
        guard Consent.hasConsented, relay.hasInbox, !service.transcriptionSettingsDirty,
              let remote = try? await relay.fetchTranscriptionSettings() else { return }
        var settings = service.load()
        settings.transcriptionLanguage = remote.language.flatMap(TranscriptionLanguage.init(rawValue:)) ?? .auto
        settings.removeFillerWords = remote.removeFillerWords
        settings.customVocabulary = remote.vocabulary
        service.save(settings)
    }
}
