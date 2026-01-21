//
//  PhoneConnectivityService.swift
//  Ramble
//

import Combine
import Foundation
import WatchConnectivity

final class PhoneConnectivityService: NSObject, ObservableObject {
    static let shared = PhoneConnectivityService()

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
