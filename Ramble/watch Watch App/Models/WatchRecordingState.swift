//
//  WatchRecordingState.swift
//  watch Watch App
//

import SwiftUI

/// Where a recording is, as far as the watch knows.
enum WatchRecordingState {
    /// The phone saved it and sent a receipt.
    case sent
    /// Handed to WatchConnectivity and the phone is reachable, or the file
    /// arrived and the watch is waiting for the phone's receipt.
    case sending
    /// Queued on the watch; it will send when the phone is around.
    case savedOnWatch
    /// Never confirmed and no longer queued (the audio file went missing).
    case notSent

    static func resolve(
        _ entry: WatchRecordingHistoryEntry,
        syncQueue: WatchSyncQueue,
        connectivity: WatchConnectivityService
    ) -> WatchRecordingState {
        if entry.syncedAt != nil { return .sent }
        guard let job = syncQueue.jobs.first(where: { $0.id == entry.id }) else { return .notSent }
        if job.handedOffAt != nil { return .sending }
        if connectivity.inFlightIDs.contains(entry.id) && connectivity.isPhoneReachable {
            return .sending
        }
        return .savedOnWatch
    }

    var label: String {
        switch self {
        case .sent: return "Sent to iPhone"
        case .sending: return "Sending to iPhone"
        case .savedOnWatch: return "Saved on watch"
        case .notSent: return "Not sent"
        }
    }

    var symbol: String {
        switch self {
        case .sent: return "checkmark.circle"
        case .sending: return "arrow.up.circle"
        case .savedOnWatch: return "applewatch"
        case .notSent: return "exclamationmark.circle"
        }
    }

    /// Neutral while things are moving or done. Orange only when audio was lost.
    var tint: Color {
        self == .notSent ? .orange : .secondary
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
}
