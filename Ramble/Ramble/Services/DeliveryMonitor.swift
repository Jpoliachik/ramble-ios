//
//  DeliveryMonitor.swift
//  Ramble
//
//  Stuck-note alerts on the phone (specs/phone.md "Phone alerts for stuck
//  notes"): one notification, as a count, with a cooldown, cleared once
//  nothing is left. The rules live in DeliveryAlertPolicy; this file decides
//  which notes count.
//
//  A phone note counts when the server hasn't accepted it 6 hours after it
//  was recorded (or released from a hold). Held and refused notes never
//  count. Watch notes alert on the watch. Agent copies still waiting show
//  only in the app (the amber card), never as a notification.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class DeliveryMonitor {
    static let shared = DeliveryMonitor()

    enum Stage: String, CaseIterable {
        case notSent
    }

    /// Notes made before this build never alert, so an upgrade doesn't
    /// surface months-old notes.
    private static let alertsSinceKey = "deliveryAlertsSince.v2"
    private static let memoryKeyPrefix = "deliveryAlertMemory.v2."
    /// The "Still waiting for your agent" notification older builds posted.
    private static let retiredIDs = ["delivery.stillWaiting", "delivery.stillWaiting.scheduled"]

    #if DEBUG
    /// Debug sheet only: the threshold in seconds, so an alert can be seen
    /// in one sitting. Phone only; release builds have no such mode.
    static let fastModeKey = "deliveryAlertsFastMode"

    static var isFastMode: Bool {
        get { UserDefaults.standard.bool(forKey: fastModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: fastModeKey) }
    }
    #endif

    static func rule(for stage: Stage) -> DeliveryAlertRule {
        #if DEBUG
        if isFastMode { return DeliveryAlertRule(threshold: 30, cooldown: 60) }
        #endif
        let hour: TimeInterval = 3600
        switch stage {
        case .notSent: return DeliveryAlertRule(threshold: 6 * hour, cooldown: 6 * hour)
        }
    }

    private let center = UNUserNotificationCenter.current()
    private var debounceTask: Task<Void, Never>?

    private init() {}

    /// Re-check whenever any recording changes.
    func start() {
        if UserDefaults.standard.object(forKey: Self.alertsSinceKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.alertsSinceKey)
        }
        center.removeDeliveredNotifications(withIdentifiers: Self.retiredIDs)
        center.removePendingNotificationRequests(withIdentifiers: Self.retiredIDs)
        UserDefaults.standard.removeObject(forKey: Self.memoryKeyPrefix + "stillWaiting")
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

        var candidates: [Stage: [StuckNoteCandidate]] = [:]
        for recording in recordings {
            guard let found = Self.stage(of: recording) else { continue }
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

    /// Whether a note counts as not sent, and since when.
    static func stage(of recording: Recording) -> (Stage, Date)? {
        let stage = DeliveryStage(recording)
        if stage == .waitingToSend, recording.source == .phone || recording.retryRequested {
            let ended = recording.createdAt.addingTimeInterval(recording.duration)
            return (.notSent, max(ended, recording.releasedAt ?? .distantPast))
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
        }
        content.sound = .default
        content.threadIdentifier = "delivery"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
