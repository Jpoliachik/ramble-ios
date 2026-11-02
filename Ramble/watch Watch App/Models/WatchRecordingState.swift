//
//  WatchRecordingState.swift
//  watch Watch App
//

import Foundation
import SwiftUI

/// Where a recording is, as far as the watch knows.
/// Derived from the history entry, the sync queue, and in-flight transfers.
enum WatchRecordingState: Equatable {
    /// Handed to WatchConnectivity and the phone is reachable.
    case sending
    /// Handed to WatchConnectivity; the system will deliver it when the phone is near.
    case waitingForPhone
    /// In the queue but not handed off yet. `retrying` after a failed attempt.
    case onWatch(retrying: Bool)
    /// Never confirmed and no longer queued (the audio file went missing).
    case notSent
    /// The phone has it.
    case onPhone(WatchPhoneStatus)

    static func resolve(
        entry: WatchRecordingHistoryEntry,
        job: WatchSyncJob?,
        isInFlight: Bool,
        isPhoneReachable: Bool
    ) -> WatchRecordingState {
        if entry.syncedAt != nil {
            return .onPhone(entry.phoneStatus ?? .received)
        }
        guard let job else { return .notSent }
        if isInFlight {
            return isPhoneReachable ? .sending : .waitingForPhone
        }
        return .onWatch(retrying: job.retryCount > 0)
    }

    var label: String {
        switch self {
        case .sending: return "Sending to iPhone"
        case .waitingForPhone: return "Waiting for iPhone"
        case .onWatch: return "On watch, will send"
        case .notSent: return "Not sent"
        case .onPhone(let status):
            switch status {
            case .received: return "Sent to iPhone"
            case .transcribing: return "Transcribing"
            case .transcribed: return "Transcribed"
            case .delivered: return "Delivered to Muse"
            case .failed: return "Check iPhone"
            }
        }
    }

    var symbol: String {
        switch self {
        case .sending: return "arrow.up.circle"
        case .waitingForPhone: return "hourglass"
        case .onWatch(let retrying): return retrying ? "arrow.clockwise.circle" : "applewatch"
        case .notSent: return "exclamationmark.circle"
        case .onPhone(let status):
            switch status {
            case .received: return "checkmark.circle"
            case .transcribing: return "waveform"
            case .transcribed: return "text.alignleft"
            case .delivered: return "checkmark.circle.fill"
            case .failed: return "exclamationmark.circle"
            }
        }
    }

    /// Neutral while things are moving or done, including retries. Orange only for real failures.
    var tint: Color {
        switch self {
        case .notSent, .onPhone(.failed):
            return .orange
        default:
            return .secondary
        }
    }

    /// True while the watch still holds the only copy.
    var isPending: Bool {
        switch self {
        case .sending, .waitingForPhone, .onWatch: return true
        case .notSent, .onPhone: return false
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
}
