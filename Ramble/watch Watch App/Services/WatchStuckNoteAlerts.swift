//
//  WatchStuckNoteAlerts.swift
//  watch Watch App
//
//  One watch notification when notes have been waiting on the watch for a
//  long time. Waiting is normal (phone left at home, a run), so the bar is
//  high and it's one alert for the whole backlog. The rules are in
//  DeliveryAlertPolicy.
//

import Foundation
import UserNotifications
import WatchKit

@MainActor
final class WatchStuckNoteAlerts {
    static let shared = WatchStuckNoteAlerts()

    /// Set from the iPhone's debug settings: thresholds in seconds, for testing.
    static let fastModeKey = "deliveryAlertsFastMode"

    static var rule: DeliveryAlertRule {
        UserDefaults.standard.bool(forKey: fastModeKey)
            ? DeliveryAlertRule(threshold: 60, cooldown: 60)
            : DeliveryAlertRule(threshold: 6 * 3600, cooldown: 6 * 3600)
    }

    private static let memoryKey = "stuckOnWatchAlertMemory"
    private static let nowID = "delivery.stuckOnWatch"
    private static let laterID = "delivery.stuckOnWatch.scheduled"

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Call whenever the watch queue changes or the app wakes.
    func update(now: Date = Date()) {
        let candidates = WatchSyncQueue.shared.jobs.map {
            StuckNoteCandidate(id: $0.id, since: $0.savedAt)
        }
        let plan = DeliveryAlertPolicy.plan(
            candidates: candidates,
            now: now,
            rule: Self.rule,
            memory: loadMemory()
        )
        saveMemory(plan.memory)
        apply(plan)
        requestPermissionIfUseful()
    }

    private func apply(_ plan: DeliveryAlertPlan) {
        if plan.clear {
            center.removeDeliveredNotifications(withIdentifiers: [Self.nowID, Self.laterID])
        }
        if let alert = plan.postNow {
            center.removeDeliveredNotifications(withIdentifiers: [Self.laterID])
            add(Self.nowID, alert, trigger: nil)
        }
        if let scheduled = plan.scheduled {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, scheduled.fireAt.timeIntervalSinceNow),
                repeats: false
            )
            add(Self.laterID, scheduled.alert, trigger: trigger)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.laterID])
        }
    }

    private func add(_ id: String, _ alert: DeliveryAlert, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = "Still on your watch"
        content.body = alert.count == 1
            ? "1 note hasn't reached your iPhone yet. It'll send when your iPhone is nearby."
            : "\(alert.count) notes haven't reached your iPhone yet. They'll send when your iPhone is nearby."
        content.sound = .default
        content.threadIdentifier = "delivery"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Asked once there's a recording to protect, never at first launch.
    private func requestPermissionIfUseful() {
        guard WKApplication.shared().applicationState == .active,
              !WatchRecordingHistory.shared.entries.isEmpty
        else { return }
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    // MARK: - Persistence

    private func loadMemory() -> DeliveryAlertMemory {
        guard let data = UserDefaults.standard.data(forKey: Self.memoryKey),
              let memory = try? JSONDecoder().decode(DeliveryAlertMemory.self, from: data)
        else { return DeliveryAlertMemory() }
        return memory
    }

    private func saveMemory(_ memory: DeliveryAlertMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: Self.memoryKey)
    }
}
