//
//  DeliveryMonitor.swift
//  Ramble
//
//  Stuck-note alerts on the phone (specs/phone.md "Phone alerts for stuck
//  notes"): one notification per kind, as a count, with a cooldown, cleared
//  once nothing is left in that kind. The rules live in DeliveryAlertPolicy;
//  this file decides which kind each note is in.
//
//  Kinds:
//  - notSent: a phone note the server hasn't accepted 6 hours after it was
//    recorded (or released from a hold). Held and refused notes never count.
//  - stillWaiting: agent copies still waiting 12 hours after the note
//    reached the server. Checked only when Ramble runs.
//
//  Watch notes alert on the watch.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class DeliveryMonitor {
    static let shared = DeliveryMonitor()

    enum Stage: String, CaseIterable {
        case notSent
        case stillWaiting
    }

    /// Debug: every threshold in seconds, so an alert can be seen in one sitting.
    static let fastModeKey = "deliveryAlertsFastMode"
    /// Notes made before this build never alert, so an upgrade doesn't
    /// surface months-old notes.
    private static let alertsSinceKey = "deliveryAlertsSince.v2"
    private static let memoryKeyPrefix = "deliveryAlertMemory.v2."

    static var isFastMode: Bool {
        get { UserDefaults.standard.bool(forKey: fastModeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: fastModeKey)
            PhoneConnectivityService.shared.pushApplicationContext()
        }
    }

    static func rule(for stage: Stage) -> DeliveryAlertRule {
        let hour: TimeInterval = 3600
        switch (stage, isFastMode) {
        case (.notSent, false): return DeliveryAlertRule(threshold: 6 * hour, cooldown: 6 * hour)
        case (.notSent, true): return DeliveryAlertRule(threshold: 30, cooldown: 60)
        // Pickup happens on the agent's side, so it's only checked, never scheduled.
        case (.stillWaiting, false): return DeliveryAlertRule(threshold: 12 * hour, cooldown: 12 * hour, canSchedule: false)
        case (.stillWaiting, true): return DeliveryAlertRule(threshold: 60, cooldown: 60, canSchedule: false)
        }
    }

    /// How long the relay keeps an agent copy nobody picked up.
    static let relayRetention: TimeInterval = 30 * 24 * 3600

    private let center = UNUserNotificationCenter.current()
    private var debounceTask: Task<Void, Never>?

    private init() {}

    /// Re-check whenever any recording changes.
    func start() {
        if UserDefaults.standard.object(forKey: Self.alertsSinceKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.alertsSinceKey)
        }
        NotificationCenter.default.addObserver(
            forName: StorageService.recordingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DeliveryMonitor.shared.evaluateSoon()
            }
        }
        evaluate()
    }

    /// Saves come in bursts (one per status change), so wait for them to settle.
    func evaluateSoon() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    func evaluate(now: Date = Date()) {
        let since = UserDefaults.standard.object(forKey: Self.alertsSinceKey) as? Date ?? now
        let all = StorageService.shared.loadRecordings()
        let recordings = all.filter { $0.createdAt >= since }
        let hasAgents = RelayService.shared.hasConnectedAgents

        var candidates: [Stage: [StuckNoteCandidate]] = [:]
        for recording in recordings {
            guard let found = Self.stage(of: recording, hasAgents: hasAgents, now: now) else { continue }
            let (stage, entered) = found
            candidates[stage, default: []].append(StuckNoteCandidate(id: recording.id, since: entered))
        }

        for stage in Stage.allCases {
            let plan = DeliveryAlertPolicy.plan(
                candidates: candidates[stage] ?? [],
                now: now,
                rule: Self.rule(for: stage),
                memory: loadMemory(stage)
            )
            saveMemory(plan.memory, for: stage)
            apply(plan, for: stage)
        }

        requestPermissionIfUseful(hasRecordings: !all.isEmpty)
    }

    /// Which kind a note is stuck in, and since when.
    static func stage(of recording: Recording, hasAgents: Bool, now: Date) -> (Stage, Date)? {
        let stage = DeliveryStage(recording, hasAgents: hasAgents)
        if stage == .waitingToSend, recording.source == .phone || recording.retryRequested {
            let ended = recording.createdAt.addingTimeInterval(recording.duration)
            return (.notSent, max(ended, recording.releasedAt ?? .distantPast))
        }
        if stage == .waitingForAgent, now.timeIntervalSince(recording.waitingSince) < relayRetention {
            return (.stillWaiting, recording.waitingSince)
        }
        return nil
    }

    // MARK: - Notifications

    private static func ids(_ stage: Stage) -> (now: String, later: String) {
        ("delivery.\(stage.rawValue)", "delivery.\(stage.rawValue).scheduled")
    }

    private func apply(_ plan: DeliveryAlertPlan, for stage: Stage) {
        let ids = Self.ids(stage)
        if plan.clear {
            center.removeDeliveredNotifications(withIdentifiers: [ids.now, ids.later])
        }
        if let alert = plan.postNow {
            center.removeDeliveredNotifications(withIdentifiers: [ids.later])
            add(ids.now, stage: stage, alert, trigger: nil)
        }
        if let scheduled = plan.scheduled {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, scheduled.fireAt.timeIntervalSinceNow),
                repeats: false
            )
            add(ids.later, stage: stage, scheduled.alert, trigger: trigger)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [ids.later])
        }
    }

    private func add(_ id: String, stage: Stage, _ alert: DeliveryAlert, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        let notes = DeliveryAlertPolicy.noteCount(alert.count)
        let one = alert.count == 1
        switch stage {
        case .notSent:
            content.title = "Not sent yet"
            content.body = "\(notes) \(one ? "hasn't" : "haven't") been sent yet. Open Ramble to send \(one ? "it" : "them")."
        case .stillWaiting:
            content.title = "Still waiting for your agent"
            content.body = "Your agent hasn't picked up \(notes) since \(Self.describe(alert.oldest))."
        }
        content.sound = .default
        content.threadIdentifier = "delivery"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// "9:12 AM" today, "yesterday", or "Tuesday".
    private static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// Asked once, in the foreground, after onboarding, when the first note exists.
    private func requestPermissionIfUseful(hasRecordings: Bool) {
        guard hasRecordings,
              UIApplication.shared.applicationState == .active,
              UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        else { return }
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    // MARK: - Persistence

    private func loadMemory(_ stage: Stage) -> DeliveryAlertMemory {
        guard let data = UserDefaults.standard.data(forKey: Self.memoryKeyPrefix + stage.rawValue),
              let memory = try? JSONDecoder().decode(DeliveryAlertMemory.self, from: data)
        else { return DeliveryAlertMemory() }
        return memory
    }

    private func saveMemory(_ memory: DeliveryAlertMemory, for stage: Stage) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: Self.memoryKeyPrefix + stage.rawValue)
    }
}
