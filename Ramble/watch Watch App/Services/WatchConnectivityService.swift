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
    private var activeTransfers: [WCSessionFileTransfer: UUID] = [:] {
        didSet {
            let ids = Set(activeTransfers.values)
            if ids != inFlightIDs { inFlightIDs = ids }
        }
    }

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
        sendMessage([
            "type": "recordingStarted",
            "device": "watch",
            "startTime": Date().timeIntervalSince1970
        ])
    }

    func sendRecordingStopped() {
        sendMessage(["type": "recordingStopped", "device": "watch"])
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

    // MARK: - File Transfer (via persistent queue)

    func transferJob(_ job: WatchSyncJob) {
        guard WCSession.default.activationState == .activated,
              !activeTransfers.values.contains(job.id),
              FileManager.default.fileExists(atPath: job.fileURL.path)
        else { return }

        let metadata = RecordingMetadata(
            recordingId: job.id.uuidString,
            createdAt: job.createdAt,
            duration: job.duration
        )
        guard let metadataData = try? JSONEncoder().encode(metadata),
              let metadataString = String(data: metadataData, encoding: .utf8)
        else { return }

        let transfer = WCSession.default.transferFile(
            job.fileURL,
            metadata: ["recording": metadataString]
        )
        activeTransfers[transfer] = job.id
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
        let delay = min(5 * pow(2.0, Double(max(attempt, 1))), 300)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
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
            // The phone has it, so the watch copy can go
            try? FileManager.default.removeItem(at: job.fileURL)
            syncQueue.markCompleted(jobId: jobId)
        }
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
        Task { @MainActor in
            self.isPhoneReachable = reachable
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

    /// The phone may send recording-state messages. They're ignored on purpose,
    /// so a tap on the watch always records on the watch.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {}

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
