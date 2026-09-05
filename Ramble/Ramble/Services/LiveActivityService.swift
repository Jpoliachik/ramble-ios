//
//  LiveActivityService.swift
//  Ramble
//

import ActivityKit
import Foundation

/// Owns the recording Live Activity. Every call is best-effort: the user can
/// disable Live Activities system-wide or per app, and a recording must never
/// fail because its activity couldn't start.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<RambleActivityAttributes>?

    /// Why the last attempt didn't produce a Live Activity, for the recording's
    /// activity log. Silent failure here was indistinguishable from the feature
    /// not being wired up at all.
    private var lastNote: String?

    func consumeLastNote() -> String? {
        defer { lastNote = nil }
        return lastNote
    }

    private init() {}

    func start(startedAt: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastNote = "Live Activity skipped: Live Activities are off for Ramble in Settings"
            return
        }
        guard activity == nil else { return }

        do {
            activity = try Activity.request(
                attributes: RambleActivityAttributes(),
                content: ActivityContent(
                    state: RambleActivityAttributes.ContentState(startedAt: startedAt),
                    staleDate: nil
                )
            )
        } catch {
            lastNote = "Live Activity failed: \(error.localizedDescription)"
            print("[LiveActivity] start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Clear anything left over from a previous process. A crash mid-recording
    /// otherwise leaves a Live Activity ticking on the lock screen forever.
    func endOrphanedActivities() {
        Task {
            for activity in Activity<RambleActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
