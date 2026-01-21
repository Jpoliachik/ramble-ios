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
        } else {
            print("WCSession activated: \(activationState.rawValue)")
        }
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
