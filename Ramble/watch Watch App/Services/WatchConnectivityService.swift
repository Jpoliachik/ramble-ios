//
//  WatchConnectivityService.swift
//  watch Watch App
//

import Combine
import Foundation
import WatchConnectivity

final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isTransferring = false
    @Published var lastTransferSuccess: Bool?

    // Phone recording state
    @Published var phoneIsRecording = false
    @Published var phoneRecordingStartTime: Date?

    // Signal when phone requests watch to stop recording
    let stopRequestReceived = PassthroughSubject<Void, Never>()

    private var pendingTransfers: [WCSessionFileTransfer] = []

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

    func transferRecording(url: URL, duration: TimeInterval) {
        guard WCSession.default.activationState == .activated else {
            print("WCSession not activated")
            return
        }

        let metadata = RecordingMetadata(
            recordingId: url.deletingPathExtension().lastPathComponent,
            createdAt: Date(),
            duration: duration
        )

        guard let metadataData = try? JSONEncoder().encode(metadata),
              let metadataString = String(data: metadataData, encoding: .utf8) else {
            return
        }

        Task { @MainActor in
            isTransferring = true
        }

        let transfer = WCSession.default.transferFile(
            url,
            metadata: ["recording": metadataString]
        )
        pendingTransfers.append(transfer)
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(
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
                handleReceivedMessage(context)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedMessage(message)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        handleReceivedMessage(applicationContext)
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            pendingTransfers.removeAll { $0 == fileTransfer }
            isTransferring = !pendingTransfers.isEmpty

            if let error = error {
                print("File transfer failed: \(error)")
                lastTransferSuccess = false
            } else {
                print("File transfer succeeded")
                lastTransferSuccess = true

                // Delete local file after successful transfer
                try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            }
        }
    }
}
