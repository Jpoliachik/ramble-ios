//
//  WatchConnectivityService.swift
//  watch Watch App
//

import Combine
import Foundation
import WatchConnectivity
import WatchKit

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    /// Recording IDs currently handed to WatchConnectivity and not yet finished.
    @Published private(set) var inFlightIDs: Set<UUID> = []
    @Published private(set) var isPhoneReachable = false
    /// False when the paired iPhone doesn't have Ramble, so notes can never
    /// leave the watch. Starts true so the alert doesn't flash at launch.
    @Published private(set) var isCompanionAppInstalled = true

    /// Maps in-flight WCSessionFileTransfer to the job ID so we can update the queue on completion.
    /// Ephemeral — if the app is killed, jobs stay in the persistent queue and retry on next launch.
    private var activeTransfers: [WCSessionFileTransfer: UUID] = [:] {
        didSet {
            let ids = Set(activeTransfers.values)
            if ids != inFlightIDs { inFlightIDs = ids }
        }
    }

    private let syncQueue = WatchSyncQueue.shared
    private var retryTask: Task<Void, Never>?
    private var retryFireDate: Date?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    struct RecordingMetadata: Codable {
        let recordingId: String
        let createdAt: Date
        let duration: TimeInterval
        /// Per-hop timing for the phone's activity log. Optional, so either
        /// side can be on an older build.
        var firstSentAt: Date?
        var sentAt: Date?
        var attempt: Int?
    }

    // MARK: - File Transfer (via persistent queue)

    /// How long a handed-off recording waits for the phone's receipt before
    /// it's sent again. The phone ignores duplicates, so resending is safe.
    /// Most receipts now come back within seconds, in the reply to a wake
    /// message (see `wakePhone`), so this only covers a phone that got the
    /// file but couldn't save it.
    static let receiptTimeout: TimeInterval = 5 * 60

    func transferJob(_ job: WatchSyncJob) {
        guard WCSession.default.activationState == .activated,
              !activeTransfers.values.contains(job.id),
              FileManager.default.fileExists(atPath: job.fileURL.path)
        else { return }
        if let handedOffAt = job.handedOffAt,
           Date().timeIntervalSince(handedOffAt) < Self.receiptTimeout {
            return // Delivered; waiting for the phone to say it saved it
        }

        let sent = syncQueue.markSent(jobId: job.id) ?? job
        let metadata = RecordingMetadata(
            recordingId: job.id.uuidString,
            createdAt: job.createdAt,
            duration: job.duration,
            firstSentAt: sent.firstSentAt,
            sentAt: sent.lastSentAt,
            attempt: sent.sendCount
        )
        guard let metadataData = try? JSONEncoder().encode(metadata),
              let metadataString = String(data: metadataData, encoding: .utf8)
        else { return }

        let transfer = WCSession.default.transferFile(
            job.fileURL,
            metadata: ["recording": metadataString]
        )
        activeTransfers[transfer] = job.id
        // transferFile alone is delivered whenever the system likes, and a
        // locked iPhone may not hand it to Ramble until it's opened (seen:
        // 40 minutes). A message wakes Ramble on the phone right away.
        wakePhone()
        scheduleBackgroundRetryIfNeeded()
    }

    // MARK: - Waking the phone

    private var lastWakeAt: Date?

    /// Sends a small message that launches Ramble on the iPhone in the
    /// background, so a file sitting in WatchConnectivity's queue reaches
    /// the app now instead of when the phone is next opened. The reply holds
    /// the ids the phone already saved, which count as receipts.
    /// Only works while the watch app is running and the phone is in reach;
    /// otherwise transferFile still gets there on its own schedule.
    func wakePhone(force: Bool = false) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        let ids = syncQueue.jobs.map(\.id.uuidString)
        guard !ids.isEmpty else { return }
        if !force, let lastWakeAt, Date().timeIntervalSince(lastWakeAt) < 3 { return }
        lastWakeAt = Date()
        Self.sendWake(recordingIds: ids)
    }

    /// Nonisolated so the reply and error handlers, which WatchConnectivity
    /// calls on its own queue, aren't tied to the main actor.
    private nonisolated static func sendWake(recordingIds: [String]) {
        WCSession.default.sendMessage(
            ["type": "wake", "recordingIds": recordingIds],
            replyHandler: { reply in
                guard let ids = receiptIDs(in: reply), !ids.isEmpty else { return }
                Task { @MainActor in
                    WatchConnectivityService.shared.handleReceipts(ids)
                }
            },
            errorHandler: { error in
                print("Wake message to iPhone failed: \(error)")
            }
        )
    }

    // MARK: - Background retry

    static let backgroundRetryTaskID = "dev.goodloop.ramble.watch.retry"
    private static let backgroundRetryInterval: TimeInterval = 10 * 60
    private var backgroundRetryDate: Date?

    /// The in-app retry timer is a Task.sleep, which never fires while
    /// watchOS has the app suspended. A background refresh gives the queue
    /// another pass (resend after the receipt timeout, pick up receipts)
    /// even if the app isn't opened again.
    func scheduleBackgroundRetryIfNeeded() {
        guard !syncQueue.jobs.isEmpty else { return }
        if let backgroundRetryDate, backgroundRetryDate > Date() { return }
        let date = Date().addingTimeInterval(Self.backgroundRetryInterval)
        backgroundRetryDate = date
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: date,
            userInfo: Self.backgroundRetryTaskID as NSString
        ) { error in
            if let error { print("Couldn't schedule watch background retry: \(error)") }
        }
    }

    /// Runs from the app refresh background task (see watchApp).
    func runBackgroundRetry() async {
        backgroundRetryDate = nil
        await waitForPendingContent()
        syncQueue.pruneOrphanedJobs()
        retryPendingTransfers()
        scheduleBackgroundRetryIfNeeded()
    }

    func retryPendingTransfers() {
        guard WCSession.default.activationState == .activated else { return }

        // Transfers queued before the app was relaunched are still owned by the
        // system. Track them again instead of sending a duplicate.
        for transfer in WCSession.default.outstandingFileTransfers {
            // Match by recording ID, not object identity: the system may hand back
            // a different WCSessionFileTransfer instance for the same transfer.
            guard let jobId = recordingId(for: transfer),
                  !activeTransfers.values.contains(jobId),
                  syncQueue.jobs.contains(where: { $0.id == jobId })
            else { continue }
            activeTransfers[transfer] = jobId
        }

        for job in syncQueue.jobs {
            transferJob(job)
        }
        // Files already handed off are skipped above, but the phone may be
        // holding them unopened. Wake it either way.
        wakePhone()
        scheduleBackgroundRetryIfNeeded()
    }

    private func recordingId(for transfer: WCSessionFileTransfer) -> UUID? {
        guard let metadataString = transfer.file.metadata?["recording"] as? String,
              let metadataData = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(RecordingMetadata.self, from: metadataData)
        else { return nil }
        return UUID(uuidString: metadata.recordingId)
    }

    /// Back off after a failed transfer: 10s, 20s, 40s ... capped at 5 minutes.
    private func scheduleRetry(attempt: Int) {
        scheduleRetry(afterSeconds: min(5 * pow(2.0, Double(max(attempt, 1))), 300))
    }

    /// One timer for every job, since a retry pass covers them all. A later
    /// request never pushes back one that's already sooner.
    private func scheduleRetry(afterSeconds delay: TimeInterval) {
        let fireDate = Date().addingTimeInterval(delay)
        if let retryFireDate, retryFireDate > Date(), retryFireDate <= fireDate { return }
        retryFireDate = fireDate
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.retryFireDate = nil
            self?.retryPendingTransfers()
        }
    }

    private func handleTransferFinished(_ fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Fall back to the metadata for transfers started before a relaunch.
        guard let jobId = activeTransfers.removeValue(forKey: fileTransfer)
                ?? recordingId(for: fileTransfer),
              let job = syncQueue.jobs.first(where: { $0.id == jobId })
        else { return }
        // Drop any other handle tracked for the same recording
        activeTransfers = activeTransfers.filter { $0.value != jobId }

        if let error {
            print("File transfer failed for job \(jobId): \(error)")
            syncQueue.markFailed(jobId: jobId)
            scheduleRetry(attempt: job.retryCount + 1)
        } else {
            // The file reached the phone, but the phone may still fail to
            // save it (locked since a restart, out of space). The watch copy
            // stays until the phone's receipt says it's safe.
            syncQueue.markHandedOff(jobId: jobId)
            scheduleRetry(afterSeconds: Self.receiptTimeout + 5)
            // The file is on the phone now. Wake Ramble there so it saves
            // it and replies with the receipt, even if the earlier wake
            // landed before the file did.
            wakePhone(force: true)
        }
    }

    /// The phone saved this recording. Only now can the watch copy go.
    private func handleReceipt(_ recordingId: UUID) {
        guard let job = syncQueue.jobs.first(where: { $0.id == recordingId }) else { return }
        activeTransfers = activeTransfers.filter { $0.value != recordingId }
        try? FileManager.default.removeItem(at: job.fileURL)
        syncQueue.markCompleted(jobId: recordingId)
        WatchStuckNoteAlerts.shared.update()
    }

    private func handleReceipts(_ ids: [String]) {
        for id in ids.compactMap(UUID.init(uuidString:)) {
            handleReceipt(id)
        }
    }

    /// Settings the phone passes along, as `["type": "settings", ...]`.
    private func applySettings(fastAlerts: Bool) {
        UserDefaults.standard.set(fastAlerts, forKey: WatchStuckNoteAlerts.fastModeKey)
        WatchStuckNoteAlerts.shared.update()
    }

    /// Pulls receipt ids out of a phone payload: `["type": "received", "recordingIds": [...]]`.
    private nonisolated static func receiptIDs(in payload: [String: Any]) -> [String]? {
        guard payload["type"] as? String == "received" else { return nil }
        return payload["recordingIds"] as? [String]
    }

    /// For the watchConnectivity background task: give WatchConnectivity
    /// time to deliver receipts that arrived while the app was asleep.
    /// Touching `shared` activates the session (see init); this only waits.
    func waitForPendingContent() async {
        guard WCSession.isSupported() else { return }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              WCSession.default.activationState != .activated || WCSession.default.hasContentPending {
            try? await Task.sleep(for: .milliseconds(200))
        }
        WatchStuckNoteAlerts.shared.update()
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WCSession activation failed: \(error)")
            return
        }
        guard activationState == .activated else { return }
        let reachable = session.isReachable
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in
            self.isPhoneReachable = reachable
            self.isCompanionAppInstalled = installed
            // Launch-time retries run before activation finishes and are
            // skipped, so pick up anything still queued now.
            self.retryPendingTransfers()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            let becameReachable = reachable && !self.isPhoneReachable
            self.isPhoneReachable = reachable
            if becameReachable {
                self.retryPendingTransfers()
            }
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in
            self.isCompanionAppInstalled = installed
            if installed {
                self.retryPendingTransfers()
            }
        }
    }

    /// Only receipts are read. Anything about the phone's own recording
    /// state is ignored on purpose, so a tap on the watch always records.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let ids = Self.receiptIDs(in: message) else { return }
        Task { @MainActor in
            self.handleReceipts(ids)
        }
    }

    /// Receipts come as queued user info, so they arrive even if the watch
    /// app wasn't running when the phone saved the recording.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if userInfo["type"] as? String == "settings",
           let fastAlerts = userInfo["deliveryAlertsFastMode"] as? Bool {
            Task { @MainActor in
                self.applySettings(fastAlerts: fastAlerts)
            }
            return
        }
        guard let ids = Self.receiptIDs(in: userInfo) else { return }
        Task { @MainActor in
            self.handleReceipts(ids)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            self.handleTransferFinished(fileTransfer, error: error)
        }
    }
}
