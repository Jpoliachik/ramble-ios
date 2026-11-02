//
//  WatchConnectivityService.swift
//  watch Watch App
//

import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    /// Recording IDs currently handed to WatchConnectivity and not yet finished.
    @Published private(set) var inFlightIDs: Set<UUID> = []
    @Published private(set) var isPhoneReachable = false

    /// Maps in-flight WCSessionFileTransfer to the job ID so we can update the queue on completion.
    /// Ephemeral — if the app is killed, jobs stay in the persistent queue and retry on next launch.
    private var activeTransfers: [WCSessionFileTransfer: UUID] = [:]

    private let syncQueue = WatchSyncQueue.shared
    private var retryTask: Task<Void, Never>?

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
    }

    // MARK: - Recording State Sync

    func sendRecordingStarted() {
        let message: [String: Any] = [
            "type": "recordingStarted",
            "device": "watch",
            "startTime": Date().timeIntervalSince1970
        ]
        sendMessage(message)
    }

    func sendRecordingStopped() {
        let message: [String: Any] = [
            "type": "recordingStopped",
            "device": "watch"
        ]
        sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send message: \(error)")
            }
        } else {
            try? WCSession.default.updateApplicationContext(message)
        }
    }

    /// The watch doesn't act on any phone message yet. The phone may still send
    /// recording-state messages ("recordingStarted", "stopRequest", "stateResponse");
    /// they are ignored on purpose, so a tap on the watch always records on the watch.
    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        default:
            break
        }
    }

    // MARK: - File Transfer (via persistent queue)

    func transferJob(_ job: WatchSyncJob) {
        guard WCSession.default.activationState == .activated else {
            print("WCSession not activated, will retry later")
            return
        }

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let fileURL = documentsDir.appendingPathComponent(job.audioFileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Audio file missing for job \(job.id), skipping")
            return
        }

        let metadata = RecordingMetadata(
            recordingId: job.id.uuidString,
            createdAt: job.createdAt,
            duration: job.duration
        )

        guard let metadataData = try? JSONEncoder().encode(metadata),
              let metadataString = String(data: metadataData, encoding: .utf8) else {
            return
        }

        let transfer = WCSession.default.transferFile(
            fileURL,
            metadata: ["recording": metadataString]
        )
        activeTransfers[transfer] = job.id
        refreshTransferState()
    }

    func retryPendingTransfers() {
        guard WCSession.default.activationState == .activated else { return }

        // Transfers queued before the app was relaunched are still owned by the
        // system. Track them again instead of sending a duplicate.
        adoptOutstandingTransfers()

        let pendingJobs = syncQueue.jobsNeedingRetry()
        guard !pendingJobs.isEmpty else { return }

        print("WatchConnectivityService: retrying \(pendingJobs.count) pending transfer(s)")
        for job in pendingJobs {
            // Don't re-send jobs already in-flight
            guard !activeTransfers.values.contains(job.id) else { continue }
            transferJob(job)
        }
    }

    private func adoptOutstandingTransfers() {
        for transfer in WCSession.default.outstandingFileTransfers {
            // Match by recording ID, not object identity: the system may hand back
            // a different WCSessionFileTransfer instance for the same transfer.
            guard let jobId = recordingId(for: transfer),
                  !activeTransfers.values.contains(jobId),
                  syncQueue.jobs.contains(where: { $0.id == jobId })
            else { continue }
            activeTransfers[transfer] = jobId
        }
        refreshTransferState()
    }

    private func recordingId(for transfer: WCSessionFileTransfer) -> UUID? {
        guard let metadataString = transfer.file.metadata?["recording"] as? String,
              let metadataData = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(RecordingMetadata.self, from: metadataData)
        else { return nil }
        return UUID(uuidString: metadata.recordingId)
    }

    private func refreshTransferState() {
        let ids = Set(activeTransfers.values)
        if ids != inFlightIDs { inFlightIDs = ids }
    }

    /// Back off after a failed transfer: 10s, 20s, 40s ... capped at 5 minutes.
    private func scheduleRetry(attempt: Int) {
        let delay = min(5 * pow(2.0, Double(max(attempt, 1))), 300)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.retryPendingTransfers()
        }
    }

    private func updateReachability(_ reachable: Bool) {
        let becameReachable = reachable && !isPhoneReachable
        isPhoneReachable = reachable
        if becameReachable {
            retryPendingTransfers()
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("WCSession activation failed: \(error)")
            return
        }
        print("WCSession activated: \(activationState.rawValue)")

        // Load any pending state from application context
        if activationState == .activated {
            let context = session.receivedApplicationContext
            let reachable = session.isReachable
            Task { @MainActor in
                if !context.isEmpty {
                    self.handleReceivedMessage(context)
                }
                self.isPhoneReachable = reachable
                // Launch-time retries run before activation finishes and are
                // skipped, so pick up anything still queued now.
                self.retryPendingTransfers()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.updateReachability(reachable)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            self.handleReceivedMessage(applicationContext)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            // Fall back to the metadata for transfers started before a relaunch.
            guard let jobId = activeTransfers.removeValue(forKey: fileTransfer)
                    ?? recordingId(for: fileTransfer),
                  syncQueue.jobs.contains(where: { $0.id == jobId })
            else {
                refreshTransferState()
                return
            }
            // Drop any other handle tracked for the same recording
            activeTransfers = activeTransfers.filter { $0.value != jobId }

            if let error = error {
                print("File transfer failed for job \(jobId): \(error)")
                syncQueue.markFailed(jobId: jobId)
                let attempts = syncQueue.jobs.first { $0.id == jobId }?.retryCount ?? 1
                scheduleRetry(attempt: attempts)
            } else {
                print("File transfer succeeded for job \(jobId)")
                // Delete local file after successful transfer
                let documentsDir = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                )[0]
                let job = syncQueue.jobs.first { $0.id == jobId }
                if let audioFileName = job?.audioFileName {
                    let fileURL = documentsDir.appendingPathComponent(audioFileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }

                syncQueue.markCompleted(jobId: jobId)
            }

            refreshTransferState()
        }
    }
}
