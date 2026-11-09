//
//  WatchNote.swift
//  watch Watch App
//
//  One note recorded on this watch, where it stands with Ramble's server,
//  and what Home and Recent show because of it. The watch uploads each note
//  straight to the relay (PUT /notes/:id) and reads its status back by ID;
//  the iPhone only gets the details and, lazily, the audio for history.
//  Everything in this file is plain logic, with no session or recorder.
//

import Foundation

/// Where a note stands with the server's upload step.
enum WatchUploadState: String, Codable {
    /// Not accepted yet. Retried until it is; never given up on.
    case waiting
    /// 402 free_notes_used: held until Ramble is unlocked.
    case heldUnlock
    /// 413: refused for good as over the length or size limit.
    case refusedTooLong
    /// 415, 400 bad_upload, or 403 suspended: refused for good for another reason.
    case refusedBadUpload
    /// The server stored the audio and created the note.
    case accepted
    /// The audio went missing before the server accepted it.
    case lost

    /// A state saved by an older build that no longer exists (such as a
    /// usage-limit hold) reads as waiting, so the note uploads again.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WatchUploadState(rawValue: raw) ?? .waiting
    }
}

/// The note's `status` on the server, once accepted.
enum WatchServerStatus: String, Codable {
    case transcribing
    case done
    case failed
}

struct WatchNoteRecord: Codable, Identifiable, Equatable {
    let id: UUID
    /// When recording started.
    let recordedAt: Date
    /// `recordedAt` as ISO 8601 with the watch's offset, exactly as sent in
    /// X-Ramble-Recorded-At, so every retry sends the same value.
    let recordedAtText: String
    let duration: TimeInterval
    let audioFileName: String

    var upload: WatchUploadState
    var status: WatchServerStatus?
    /// The server's `result`: "transcript", "no_speech", "audio_rejected",
    /// "retries_exhausted", or nil.
    var result: String?
    /// First line of the transcript, for Recent. The watch never keeps more.
    var preview: String?
    /// Start of the 6-hour stuck clock: the stop, or the release from a hold.
    var waitingSince: Date
    /// Failed attempts in a row, for the 10 s doubling to 5 min backoff.
    var failureCount: Int
    /// The next timed retry while the app is open: the backoff, or the wait
    /// the server asked for (429).
    var nextAttemptAt: Date?
    /// When the note reached a final state (done, failed, refused, lost).
    var finalAt: Date?
    /// When the watch learned the transcript (or silence) was ready.
    var doneAt: Date?
    /// When the person first saw it in Recent (failed, refused, lost).
    var firstSeenAt: Date?
    /// Left Recent. The record stays only while the audio is still kept.
    var hiddenFromRecent: Bool
    /// The iPhone's receipt says it saved the audio.
    var phoneHasAudio: Bool
    var audioDeleted: Bool
    var lastPolledAt: Date?

    init(id: UUID, recordedAt: Date, duration: TimeInterval, audioFileName: String, now: Date = Date()) {
        self.id = id
        self.recordedAt = recordedAt
        self.recordedAtText = WatchDates.offsetString(recordedAt)
        self.duration = duration
        self.audioFileName = audioFileName
        self.upload = .waiting
        self.status = nil
        self.result = nil
        self.preview = nil
        self.waitingSince = now
        self.failureCount = 0
        self.nextAttemptAt = nil
        self.finalAt = nil
        self.doneAt = nil
        self.firstSeenAt = nil
        self.hiddenFromRecent = false
        self.phoneHasAudio = false
        self.audioDeleted = false
        self.lastPolledAt = nil
    }

    var fileURL: URL {
        WatchNoteStore.documentsURL.appendingPathComponent(audioFileName)
    }

    /// Done, failed for good, refused for good, or lost. From here the audio
    /// only waits for the iPhone's receipt, at most 30 days.
    var isFinal: Bool {
        switch upload {
        case .refusedTooLong, .refusedBadUpload, .lost:
            return true
        case .accepted:
            return status == .done || status == .failed
        case .waiting, .heldUnlock:
            return false
        }
    }

    /// Still to be accepted by the server (waiting or held).
    var isUnaccepted: Bool {
        upload == .waiting || upload == .heldUnlock
    }

    /// Accepted and the watch still needs its final status.
    var needsPolling: Bool {
        upload == .accepted && (status == nil || status == .transcribing)
    }

    /// The hold value the iPhone gets in note details.
    var holdValue: String {
        switch upload {
        case .heldUnlock: return "unlock"
        case .refusedTooLong, .refusedBadUpload: return "refused"
        default: return "none"
        }
    }

    var refusedReason: String? {
        switch upload {
        case .refusedTooLong: return "too_long"
        case .refusedBadUpload: return "bad_upload"
        default: return nil
        }
    }
}

// MARK: - What Recent and Home show

enum WatchNoteDisplay: Equatable {
    case waiting
    case uploading
    case transcribing
    case done(preview: String?)
    case silent
    case heldUnlock
    case stuck(since: Date)
    case failed
    case lost
    case tooLong
    case couldntSend

    enum Section {
        case needsYou
        case waiting
        case done
    }

    var section: Section {
        switch self {
        case .waiting, .uploading, .transcribing: return .waiting
        case .done, .silent: return .done
        case .heldUnlock, .stuck, .failed, .lost, .tooLong, .couldntSend: return .needsYou
        }
    }

    /// The line under the row's time and length.
    var line: String? {
        switch self {
        case .waiting, .uploading, .transcribing: return nil
        case .done(let preview): return preview
        case .silent: return "No speech detected"
        case .heldUnlock: return "Unlock to send"
        case .stuck(let since): return WatchFormat.waitingReason(since: since)
        case .failed: return "Couldn't transcribe"
        case .lost: return "Audio lost"
        case .tooLong: return "Too long to transcribe"
        case .couldntSend: return "Couldn't send"
        }
    }

    /// Failed, refused or lost: they leave Recent 24 hours after first seen.
    var isFinalProblem: Bool {
        switch self {
        case .failed, .lost, .tooLong, .couldntSend: return true
        default: return false
        }
    }

    static func resolve(
        _ note: WatchNoteRecord,
        isUploading: Bool,
        stuckAfter: TimeInterval,
        now: Date
    ) -> WatchNoteDisplay {
        switch note.upload {
        case .waiting:
            if now.timeIntervalSince(note.waitingSince) >= stuckAfter {
                return .stuck(since: note.waitingSince)
            }
            return isUploading ? .uploading : .waiting
        case .heldUnlock:
            return .heldUnlock
        case .refusedTooLong:
            return .tooLong
        case .refusedBadUpload:
            return .couldntSend
        case .lost:
            return .lost
        case .accepted:
            switch note.status {
            case .done:
                return note.result == "no_speech" ? .silent : .done(preview: note.preview)
            case .failed:
                return .failed
            case .transcribing, .none:
                return .transcribing
            }
        }
    }
}

/// A note with what it shows, so Home and Recent agree on every note.
struct WatchNote: Identifiable {
    let record: WatchNoteRecord
    let display: WatchNoteDisplay
    var id: UUID { record.id }
}

/// The one mark on the history button. Highest wins.
enum WatchHistoryBadge: Equatable {
    case none
    /// Waiting to upload. A still gray dot.
    case waiting
    /// Uploading or being transcribed. A spinning ring.
    case moving
    /// Something needs the person. A red dot.
    case needsYou

    /// A lost note stops counting once it's been seen in Recent, since
    /// there is nothing left to do about it.
    static func resolve(_ notes: [WatchNote]) -> WatchHistoryBadge {
        var badge = WatchHistoryBadge.none
        for note in notes {
            switch note.display {
            case .heldUnlock, .stuck, .failed, .tooLong, .couldntSend:
                return .needsYou
            case .lost:
                if note.record.firstSeenAt == nil { return .needsYou }
            case .uploading, .transcribing:
                badge = .moving
            case .waiting:
                if badge == .none { badge = .waiting }
            case .done, .silent:
                break
            }
        }
        return badge
    }
}

/// The short alert at the bottom left. One at a time, in priority order.
enum WatchAlert: String, Identifiable, Hashable {
    case micOff
    case micBusy
    case noPhone
    case setUp
    case unlock

    var id: String { rawValue }

    /// Bar words: an icon plus at most 8 characters, counting spaces.
    var shortText: String {
        switch self {
        case .micOff: return "Mic off"
        case .micBusy: return "Mic busy"
        case .noPhone: return "No phone"
        case .setUp: return "Set up"
        case .unlock: return "Unlock"
        }
    }

    var symbol: String {
        switch self {
        case .micOff, .micBusy: return "mic.slash"
        case .noPhone: return "iphone.slash"
        case .setUp: return "iphone"
        case .unlock: return "lock.fill"
        }
    }

    /// Red when nothing can be recorded. Gray when recording still works.
    var isBlocking: Bool { self == .micOff || self == .micBusy }

    /// Tapping again is the fix for a busy mic, so it has no detail screen.
    var hasDetail: Bool { self != .micBusy }

    var detailTitle: String {
        switch self {
        case .micOff: return "Microphone is off"
        case .micBusy: return "Microphone is busy"
        case .noPhone: return "Ramble isn't on your iPhone"
        case .setUp: return "Open Ramble on your iPhone"
        case .unlock: return "Unlock to send"
        }
    }

    var detailBody: [String] {
        switch self {
        case .micOff:
            return [
                "Ramble can't hear you, so nothing gets recorded.",
                "On your watch, open Settings, then Privacy & Security, then Microphone, and turn on Ramble."
            ]
        case .micBusy:
            return []
        case .noPhone:
            return [
                "Your notes are safe on this watch, but they can't reach your agent yet.",
                "Install Ramble on your iPhone and open it once. Waiting notes will send on their own."
            ]
        case .setUp:
            return [
                "Your notes are safe on this watch, but they can't send yet.",
                "Open Ramble on your iPhone once. Waiting notes will send on their own."
            ]
        case .unlock:
            return [
                "You've used your free notes. Your notes are safe on this watch.",
                "Unlock Ramble on your iPhone and they'll send on their own."
            ]
        }
    }

    static func resolve(
        micDenied: Bool,
        micBusy: Bool,
        companionAppInstalled: Bool,
        isConnected: Bool,
        hasUnlockHold: Bool
    ) -> WatchAlert? {
        if micDenied { return .micOff }
        if micBusy { return .micBusy }
        if !companionAppInstalled { return .noPhone }
        if !isConnected { return .setUp }
        if hasUnlockHold { return .unlock }
        return nil
    }
}

// MARK: - Formatting

enum WatchDates {
    /// ISO 8601 with the watch's own offset, e.g. 2026-11-06T09:14:03-08:00.
    static func offsetString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

}

enum WatchFormat {
    static func duration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// The recording timer: elapsed, or from 55:00 the time left with a
    /// minus sign ("−4:59").
    static func timer(elapsed: TimeInterval, cap: TimeInterval, warnAt: TimeInterval) -> String {
        guard elapsed >= warnAt else { return duration(elapsed) }
        let left = max(0, Int((cap - elapsed).rounded(.up)))
        return String(format: "\u{2212}%d:%02d", left / 60, left % 60)
    }

    /// Spoken form for VoiceOver, e.g. "1 minute, 4 seconds".
    static func spokenDuration(_ duration: TimeInterval) -> String {
        Duration.seconds(Int(duration)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "Waiting 6 hours", "Waiting 7 hours", or minutes under an hour (the
    /// debug threshold is a minute, so this has to read well there too).
    static func waitingReason(since: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(since))
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return "Waiting \(minutes) min"
        }
        let hours = Int(seconds / 3600)
        return hours == 1 ? "Waiting 1 hour" : "Waiting \(hours) hours"
    }

    /// First non-empty line of a transcript, kept short.
    static func firstLine(_ transcript: String?) -> String? {
        guard let transcript else { return nil }
        let line = transcript
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, !line.isEmpty else { return nil }
        return String(line.prefix(160))
    }
}
