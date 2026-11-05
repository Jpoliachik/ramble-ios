//
//  DeliveryAlertPolicy.swift
//
//  Decides when to tell someone a note is stuck. Pure logic with no
//  notification code, so the rules can be tested on their own.
//
//  The same file lives in the iPhone and watch targets; keep them identical.
//
//  Rules, per stage (one stage = one kind of alert):
//  1. A note is stuck once it has been in the stage for `threshold`.
//  2. One alert covers every note in the stage, as a count. Never one per
//     note. Everything it covers counts as alerted.
//  3. At most one alert per `cooldown`.
//  4. A note only triggers an alert once. A new alert needs a newly stuck note.
//  5. When nothing is left in the stage, the alert is cleared.
//  6. Alerts that can be predicted are scheduled with the system ahead of
//     time, so they fire even if the app never gets to run again.
//

import Foundation

struct StuckNoteCandidate: Equatable {
    let id: UUID
    /// When the note entered this stage.
    let since: Date
}

struct DeliveryAlertRule: Equatable {
    /// How long a note sits in the stage before it counts as stuck.
    var threshold: TimeInterval
    /// Minimum time between two alerts for the stage.
    var cooldown: TimeInterval
    /// False when only a fresh check can tell (e.g. agent pickup, which
    /// happens elsewhere), so nothing is scheduled ahead of time.
    var canSchedule: Bool = true
}

/// What the policy remembers between runs. Persist it per stage.
struct DeliveryAlertMemory: Codable, Equatable {
    var lastAlertAt: Date?
    var alertedIDs: Set<UUID> = []
    /// An alert handed to the system to show later, and the notes it covers.
    var scheduledAt: Date?
    var scheduledIDs: Set<UUID> = []
}

struct DeliveryAlert: Equatable {
    let count: Int
    let oldest: Date
}

struct ScheduledDeliveryAlert: Equatable {
    let fireAt: Date
    let alert: DeliveryAlert
}

struct DeliveryAlertPlan: Equatable {
    /// Nothing is in the stage any more: remove its alerts from view.
    var clear = false
    /// Show this now.
    var postNow: DeliveryAlert?
    /// Have the system show this later, replacing any earlier schedule.
    /// Nil means cancel whatever was scheduled.
    var scheduled: ScheduledDeliveryAlert?
    var memory: DeliveryAlertMemory
}

enum DeliveryAlertPolicy {
    static func plan(
        candidates: [StuckNoteCandidate],
        now: Date,
        rule: DeliveryAlertRule,
        memory previous: DeliveryAlertMemory
    ) -> DeliveryAlertPlan {
        var memory = previous

        // A scheduled alert whose time has passed was shown by the system.
        if let fired = memory.scheduledAt, fired <= now {
            memory.lastAlertAt = max(memory.lastAlertAt ?? fired, fired)
            memory.alertedIDs.formUnion(memory.scheduledIDs)
        }
        memory.scheduledAt = nil
        memory.scheduledIDs = []

        // Forget notes that moved on, so they can alert again if they come back.
        memory.alertedIDs.formIntersection(Set(candidates.map(\.id)))

        guard !candidates.isEmpty else {
            return DeliveryAlertPlan(clear: true, memory: memory)
        }

        var plan = DeliveryAlertPlan(memory: memory)
        let isStuck = { (note: StuckNoteCandidate, at: Date) in
            at.timeIntervalSince(note.since) >= rule.threshold
        }

        let hasNew = candidates.contains { isStuck($0, now) && !memory.alertedIDs.contains($0.id) }
        if hasNew && now >= cooldownEnd(memory, rule) {
            // Everything waiting goes in one alert, even notes that only just
            // arrived, so one bad stretch means one alert.
            plan.postNow = summary(of: candidates)
            plan.memory.lastAlertAt = now
            plan.memory.alertedIDs.formUnion(candidates.map(\.id))
        }

        guard rule.canSchedule else { return plan }

        // The next moment a note that hasn't alerted yet would justify one.
        let waiting = candidates.filter { !plan.memory.alertedIDs.contains($0.id) }
        guard let earliest = waiting.map({ $0.since.addingTimeInterval(rule.threshold) }).min() else {
            return plan
        }
        let fireAt = max(earliest, cooldownEnd(plan.memory, rule), now.addingTimeInterval(1))
        plan.scheduled = ScheduledDeliveryAlert(fireAt: fireAt, alert: summary(of: candidates))
        plan.memory.scheduledAt = fireAt
        plan.memory.scheduledIDs = Set(candidates.map(\.id))
        return plan
    }

    private static func cooldownEnd(_ memory: DeliveryAlertMemory, _ rule: DeliveryAlertRule) -> Date {
        memory.lastAlertAt.map { $0.addingTimeInterval(rule.cooldown) } ?? .distantPast
    }

    private static func summary(of notes: [StuckNoteCandidate]) -> DeliveryAlert {
        DeliveryAlert(count: notes.count, oldest: notes.map(\.since).min() ?? Date())
    }

    /// "1 note" / "3 notes"
    static func noteCount(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }
}
