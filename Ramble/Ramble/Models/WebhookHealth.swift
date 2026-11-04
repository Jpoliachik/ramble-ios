//
//  WebhookHealth.swift
//  Ramble
//

import SwiftUI

/// Aggregated health indicator for the user-configured webhook destination.
/// Derived from the most recently resolved per-recording `webhookStatus`.
enum WebhookHealth {
    case untested
    case healthy
    case error

    var color: Color {
        switch self {
        case .healthy: return .green
        case .error: return .red
        case .untested: return .yellow
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .healthy: return "Last delivery succeeded"
        case .error: return "Last delivery failed"
        case .untested: return "Webhook not yet tested"
        }
    }

    static func compute(from recordings: [Recording]) -> WebhookHealth {
        let mostRecentResolved = recordings
            .sorted { $0.createdAt > $1.createdAt }
            .first { recording in
                recording.webhookStatus == .delivered || recording.webhookStatus == .failed
            }

        switch mostRecentResolved?.webhookStatus {
        case .delivered: return .healthy
        case .failed: return .error
        default: return .untested
        }
    }
}
