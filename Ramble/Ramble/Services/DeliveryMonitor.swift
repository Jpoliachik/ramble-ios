//
//  DeliveryMonitor.swift
//  Ramble
//
//  Tells the user, with a local notification, when notes are stuck on the
//  way to their agent. Smart and rare on purpose: one alert per stage, as a
//  count, with a cooldown, cleared once things move again. The rules live in
//  DeliveryAlertPolicy; this file decides which stage each note is in.
//
//  Stages:
//  - stuckOnPhone: on this phone but not sent yet (offline, locked, iOS gave
//    no background time). Opening Ramble usually sends them.
//  - needsYou: can't go anywhere without the user (no agent connected,
//    the relay or webhook rejected it, transcription gave up).
//  - notPickedUp: the relay has it, the agent hasn't taken it.
//
//  Notes on the watch are covered by the watch's own alert.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class DeliveryMonitor {
    static let shared = DeliveryMonitor()

    enum Stage: String, CaseIterable {
        case stuckOnPhone
        case needsYou
        case notPickedUp
    }

    /// Debug: every threshold in seconds, so an alert can be seen in one sitting.
    static let fastModeKey = "deliveryAlertsFastMode"
    /// Notes made before this build never alert, so an upgrade doesn't
    /// surface months-old failures.
    private static let alertsSinceKey = "deliveryAlertsSince"
    private static let memoryKeyPrefix = "deliveryAlertMemory."

    static var isFastMode: Bool {
        get { UserDefaults.standard.bool(forKey: fastModeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: fastModeKey)
            PhoneConnectivityService.shared.sendAlertFastMode(newValue)
        }
    }

    /// The tunable part. Defaults are a judgment call; adjust from real use.
    static func rule(for stage: Stage) -> DeliveryAlertRule {
        let hour: TimeInterval = 3600
        switch (stage, isFastMode) {
        case (.stuckOnPhone, false): return DeliveryAlertRule(threshold: 1 * hour, cooldown: 6 * hour)
        case (.stuckOnPhone, true): return DeliveryAlertRule(threshold: 30, cooldown: 60)
        // Short wait so a burst of failures becomes one alert.
        case (.needsYou, false): return DeliveryAlertRule(threshold: 120, cooldown: 6 * hour)
        case (.needsYou, true): return DeliveryAlertRule(threshold: 5, cooldown: 60)
        // Pickup happens on the agent's side, so it's only checked, never scheduled.
        case (.notPickedUp, false): return DeliveryAlertRule(threshold: 12 * hour, cooldown: 12 * hour, canSchedule: false)
        case (.notPickedUp, true): return DeliveryAlertRule(threshold: 60, cooldown: 60, canSchedule: false)
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
        let recordings = StorageService.shared.loadRecordings().filter { $0.createdAt >= since }

        var candidates: [Stage: [StuckNoteCandidate]] = [:]
        for recording in recordings {
            guard let found = Self.stage(of: recording, now: now) else { continue }
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

        requestPermissionIfUseful(hasRecordings: !recordings.isEmpty)
    }

    /// Which stage a note is stuck in, and since when. Nil when it's done or
    /// has nowhere to go (no agent or webhook was ever set up for it).
    static func stage(of recording: Recording, now: Date) -> (Stage, Date)? {
        let arrived = recording.receivedAt ?? recording.createdAt.addingTimeInterval(recording.duration)
        let inFlight: Set<WebhookStatus> = [.pending, .sending]

        if recording.status == .failed || recording.relayStatus == .failed || recording.webhookStatus == .failed {
            return (.needsYou, recording.activityLog.last?.timestamp ?? arrived)
        }
        if recording.status == .recorded || recording.status == .transcribing
            || recording.relayStatus.map({ inFlight.contains($0) }) == true
            || recording.webhookStatus.map({ inFlight.contains($0) }) == true {
            return (.stuckOnPhone, arrived)
        }
        if recording.isWaitingForAgent, let uploaded = recording.relayUploadedAt,
           now.timeIntervalSince(uploaded) < RelayQueueService.relayRetention {
            return (.notPickedUp, uploaded)
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
        case .stuckOnPhone:
            content.title = "Not sent yet"
            content.body = "\(notes) \(one ? "hasn't" : "haven't") been sent yet. Open Ramble to send \(one ? "it" : "them")."
        case .needsYou:
            content.title = "Couldn't send"
            content.body = "\(notes) couldn't be sent. Open Ramble to see why."
        case .notPickedUp:
            content.title = "Not picked up"
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

    /// Asked in the foreground once there's a note worth protecting, not
    /// during onboarding.
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
