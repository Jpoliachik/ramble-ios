//
//  PhoneConnectivityService.swift
//  Ramble
//

import Combine
import Foundation
import WatchConnectivity

final class PhoneConnectivityService: NSObject, ObservableObject {
    static let shared = PhoneConnectivityService()

    // Watch recording state
    @Published var watchIsRecording = false
    @Published var watchRecordingStartTime: Date?

    // Signal when watch requests phone to stop recording
    let stopRequestReceived = PassthroughSubject<Void, Never>()

    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared

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
            "device": "phone",
            "startTime": Date().timeIntervalSince1970
        ]
        sendMessage(message)
    }

    func sendRecordingStopped() {
        let message: [String: Any] = [
            "type": "recordingStopped",
            "device": "phone"
        ]
        sendMessage(message)
    }

    func requestWatchStopRecording() {
        let message: [String: Any] = ["type": "stopRequest"]
        sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send message: \(error)")
            }
        } else {
            // Fallback: update application context for when watch becomes reachable
            try? WCSession.default.updateApplicationContext(message)
        }
    }

    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "recordingStarted":
                if let startTime = message["startTime"] as? TimeInterval {
                    self.watchRecordingStartTime = Date(timeIntervalSince1970: startTime)
                }
                self.watchIsRecording = true

            case "recordingStopped":
                self.watchIsRecording = false
                self.watchRecordingStartTime = nil

            case "stopRequest":
                self.stopRequestReceived.send()

            default:
                break
            }
        }
    }
}

extension PhoneConnectivityService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("Phone WCSession activation failed: \(error)")
        } else {
            print("Phone WCSession activated: \(activationState.rawValue)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        WCSession.default.activate()
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

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadataString = file.metadata?["recording"] as? String,
              let metadataData = metadataString.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(RecordingMetadata.self, from: metadataData)
        else {
            print("Failed to parse watch recording metadata")
            return
        }

        let audioFileName = "\(metadata.recordingId).m4a"
        let destinationURL = StorageService.audioDirectory.appendingPathComponent(audioFileName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: destinationURL)

            let recording = Recording(
                id: UUID(uuidString: metadata.recordingId) ?? UUID(),
                createdAt: metadata.createdAt,
                duration: metadata.duration,
                audioFileName: audioFileName
            )

            Task { @MainActor in
                storageService.addRecording(recording)
                transcriptionQueue.enqueue(recordingId: recording.id)
            }

            print("Received recording from watch: \(metadata.recordingId)")

        } catch {
            print("Failed to save watch recording: \(error)")
        }
    }
}
