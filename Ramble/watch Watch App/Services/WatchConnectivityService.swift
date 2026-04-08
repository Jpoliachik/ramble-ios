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

    @Published var isTransferring = false
    @Published var lastTransferSuccess: Bool?

    // Phone recording state
    @Published var phoneIsRecording = false
    @Published var phoneRecordingStartTime: Date?

    // Signal when phone requests watch to stop recording
    let stopRequestReceived = PassthroughSubject<Void, Never>()

    /// Maps in-flight WCSessionFileTransfer to the job ID so we can update the queue on completion.
    /// Ephemeral — if the app is killed, jobs stay in the persistent queue and retry on next launch.
    private var activeTransfers: [WCSessionFileTransfer: UUID] = [:]

    private let syncQueue = WatchSyncQueue.shared

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

    func requestPhoneStopRecording() {
        let message: [String: Any] = ["type": "stopRequest"]
        sendMessage(message)
    }

    func queryPhoneState() {
        let message: [String: Any] = ["type": "stateQuery"]
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

    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "recordingStarted":
                if let startTime = message["startTime"] as? TimeInterval {
                    self.phoneRecordingStartTime = Date(timeIntervalSince1970: startTime)
                }
                self.phoneIsRecording = true

            case "recordingStopped":
                self.phoneIsRecording = false
                self.phoneRecordingStartTime = nil

            case "stopRequest":
                self.stopRequestReceived.send()

            case "stateResponse":
                let isRecording = message["isRecording"] as? Bool ?? false
                if isRecording, let startTime = message["startTime"] as? TimeInterval {
                    self.phoneRecordingStartTime = Date(timeIntervalSince1970: startTime)
                } else {
                    self.phoneRecordingStartTime = nil
                }
                self.phoneIsRecording = isRecording

            default:
                break
            }
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

        isTransferring = true
        syncQueue.updateSyncingState(isActive: true)

        let transfer = WCSession.default.transferFile(
            fileURL,
            metadata: ["recording": metadataString]
        )
        activeTransfers[transfer] = job.id
    }

    func retryPendingTransfers() {
        let pendingJobs = syncQueue.jobsNeedingRetry()
        guard !pendingJobs.isEmpty else { return }

        print("WatchConnectivityService: retrying \(pendingJobs.count) pending transfer(s)")
        for job in pendingJobs {
            // Don't re-send jobs already in-flight
            guard !activeTransfers.values.contains(job.id) else { continue }
            transferJob(job)
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
            if !context.isEmpty {
                Task { @MainActor in
                    self.handleReceivedMessage(context)
                }
            }
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
            guard let jobId = activeTransfers.removeValue(forKey: fileTransfer) else {
                // Transfer we don't know about (possibly from before app restart)
                // Update UI state based on remaining transfers
                isTransferring = !activeTransfers.isEmpty
                return
            }

            if let error = error {
                print("File transfer failed for job \(jobId): \(error)")
                lastTransferSuccess = false
                syncQueue.markFailed(jobId: jobId)
            } else {
                print("File transfer succeeded for job \(jobId)")
                lastTransferSuccess = true

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

            isTransferring = !activeTransfers.isEmpty
            syncQueue.updateSyncingState(isActive: !activeTransfers.isEmpty)
        }
    }
}
