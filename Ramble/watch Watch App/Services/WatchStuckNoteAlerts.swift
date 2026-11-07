//
//  WatchStuckNoteAlerts.swift
//  watch Watch App
//
//  One watch notification when a note has gone 6 hours without the server
//  accepting it. Waiting is normal (phone left at home, a run), so the bar
//  is high and it's one alert for the whole backlog. Held and refused notes
//  never count. The rules are in DeliveryAlertPolicy.
//

import Foundation
import UserNotifications
import WatchKit

@MainActor
final class WatchStuckNoteAlerts {
    static let shared = WatchStuckNoteAlerts()

    static let rule = DeliveryAlertRule(threshold: 6 * 3600, cooldown: 6 * 3600)

    private static let memoryKey = "stuckOnWatchAlertMemory"
    private static let nowID = "delivery.stuckOnWatch"
    private static let laterID = "delivery.stuckOnWatch.scheduled"
    private static let askedKey = "askedForNotificationPermission"

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Call whenever a note changes or the app wakes.
    func update(now: Date = Date()) {
        // Only notes the server hasn't accepted and isn't holding or refusing.
        // A released hold counts its 6 hours from the release.
        let candidates = WatchNoteStore.shared.notes
            .filter { $0.upload == .waiting }
            .map { StuckNoteCandidate(id: $0.id, since: $0.waitingSince) }
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
            // An upload may finish while the app is asleep. Wake a few
            // minutes before the alert so a note the server accepted in the
            // meantime cancels it.
            WatchRelayService.shared.scheduleBackgroundRefresh(
                before: scheduled.fireAt.addingTimeInterval(-5 * 60)
            )
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.laterID])
        }
    }

    private func add(_ id: String, _ alert: DeliveryAlert, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = "Still on your watch"
        content.body = alert.count == 1
            ? "1 note hasn't reached Ramble yet. It's safe here and will send on its own."
            : "\(alert.count) notes haven't reached Ramble yet. They're safe here and will send on their own."
        content.sound = .default
        content.threadIdentifier = "delivery"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Asked once, only while the app is open and a note exists.
    private func requestPermissionIfUseful() {
        guard WKApplication.shared().applicationState == .active,
              !WatchNoteStore.shared.notes.isEmpty,
              !UserDefaults.standard.bool(forKey: Self.askedKey)
        else { return }
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            UserDefaults.standard.set(true, forKey: Self.askedKey)
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
