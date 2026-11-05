//
//  WatchRecordingState.swift
//  watch Watch App
//
//  Where each note is, as far as the watch knows, and what the home screen
//  shows because of it. The watch's finish line is "the iPhone has it": it
//  never hears from the agent. Everything here is plain logic so it can be
//  tested without a session or a recorder.
//

import Foundation

/// Where one note is.
enum WatchDeliveryState: Equatable {
    /// The phone saved it and sent a receipt.
    case onPhone
    /// Being transferred right now, with the phone in reach.
    case moving
    /// Queued on the watch. Normal when the phone is away.
    case waiting
    /// Moving or waiting for longer than the stuck threshold.
    case stuck(since: Date)
    /// Never confirmed and no longer queued: the audio went missing.
    case lost

    /// Stuck and lost notes are the only ones that need the person.
    var needsYou: Bool {
        switch self {
        case .stuck, .lost: return true
        default: return false
        }
    }

    static func resolve(
        _ entry: WatchRecordingHistoryEntry,
        job: WatchSyncJob?,
        isInFlight: Bool,
        isPhoneReachable: Bool,
        stuckAfter: TimeInterval,
        now: Date
    ) -> WatchDeliveryState {
        if entry.syncedAt != nil { return .onPhone }
        guard let job else { return .lost }
        if now.timeIntervalSince(job.savedAt) >= stuckAfter { return .stuck(since: job.savedAt) }
        if isInFlight && isPhoneReachable { return .moving }
        return .waiting
    }
}

/// A history entry with its resolved state.
struct WatchNote: Identifiable {
    let entry: WatchRecordingHistoryEntry
    let state: WatchDeliveryState
    var id: UUID { entry.id }
}

/// The one mark on the history button. Highest wins.
enum WatchHistoryBadge: Equatable {
    case none
    /// Notes are waiting for the phone. A still gray dot.
    case waiting
    /// A transfer is running. A spinning ring.
    case moving
    /// Something needs the person. A red dot.
    case needsYou

    /// A lost note stops counting as "needs you" once it's been seen in
    /// Recent, since there is nothing left to fix. A stuck note counts until
    /// it reaches the phone.
    static func resolve(_ notes: [WatchNote], seenLostIDs: Set<UUID>) -> WatchHistoryBadge {
        var badge = WatchHistoryBadge.none
        for note in notes {
            switch note.state {
            case .stuck:
                return .needsYou
            case .lost:
                if !seenLostIDs.contains(note.id) { return .needsYou }
            case .moving:
                badge = .moving
            case .waiting:
                if badge == .none { badge = .waiting }
            case .onPhone:
                break
            }
        }
        return badge
    }
}

/// The short alert at the bottom left. One at a time, in priority order.
enum WatchAlert: String, Identifiable, Hashable {
    /// Microphone permission is off. Stays until it's back on.
    case micOff
    /// A start failed for another reason, usually a call. Shown for 3 s.
    case micBusy
    /// The paired iPhone doesn't have Ramble, so notes can't leave the watch.
    case noPhone

    var id: String { rawValue }

    /// Bar words: an icon plus at most 8 characters, so it never runs under
    /// the history button. Full sentences live on the detail screen.
    var shortText: String {
        switch self {
        case .micOff: return "Mic off"
        case .micBusy: return "Mic busy"
        case .noPhone: return "No phone"
        }
    }

    var symbol: String {
        switch self {
        case .micOff, .micBusy: return "mic.slash"
        case .noPhone: return "iphone.slash"
        }
    }

    /// Red when it stops a recording. Gray when recording still works.
    var isBlocking: Bool { self != .noPhone }

    /// Tapping again is the fix for a busy mic, so it has no detail screen.
    var hasDetail: Bool { self != .micBusy }

    var detailTitle: String {
        switch self {
        case .micOff: return "Microphone is off"
        case .micBusy: return "Microphone is busy"
        case .noPhone: return "Ramble isn't on your iPhone"
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
            return ["Something else is using the microphone, like a call. Try again in a moment."]
        case .noPhone:
            return [
                "Your notes are safe on this watch, but they can't reach your agent yet.",
                "Install Ramble on your iPhone and open it once. Waiting notes will send on their own."
            ]
        }
    }

    static func resolve(micDenied: Bool, micBusy: Bool, companionAppInstalled: Bool) -> WatchAlert? {
        if micDenied { return .micOff }
        if micBusy { return .micBusy }
        if !companionAppInstalled { return .noPhone }
        return nil
    }
}

/// Reads the live services once, so Home and Recent agree on every note.
@MainActor
enum WatchDelivery {
    static func notes(now: Date = Date()) -> [WatchNote] {
        let jobs = Dictionary(WatchSyncQueue.shared.jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let connectivity = WatchConnectivityService.shared
        let stuckAfter = WatchStuckNoteAlerts.rule.threshold
        return WatchRecordingHistory.shared.entries.map { entry in
            let state = WatchDeliveryState.resolve(
                entry,
                job: jobs[entry.id],
                isInFlight: connectivity.inFlightIDs.contains(entry.id),
                isPhoneReachable: connectivity.isPhoneReachable,
                stuckAfter: stuckAfter,
                now: now
            )
            return WatchNote(entry: entry, state: state)
        }
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

    /// Spoken form for VoiceOver, e.g. "1 minute, 4 seconds".
    static func spokenDuration(_ duration: TimeInterval) -> String {
        Duration.seconds(Int(duration)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "Waiting 7 hours", or minutes under an hour (the debug threshold is
    /// a minute, so this has to read well at small values too).
    static func waitingReason(since: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(since))
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return "Waiting \(minutes) min"
        }
        let hours = Int(seconds / 3600)
        return hours == 1 ? "Waiting 1 hour" : "Waiting \(hours) hours"
    }
}
