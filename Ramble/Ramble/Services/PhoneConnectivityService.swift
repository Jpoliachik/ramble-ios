//
//  PhoneConnectivityService.swift
//  Ramble
//

import Combine
import Foundation
import UIKit
import WatchConnectivity

final class PhoneConnectivityService: NSObject, ObservableObject {
    static let shared = PhoneConnectivityService()

    // Watch recording state
    @Published var watchIsRecording = false
    @Published var watchRecordingStartTime: Date?

    // Phone's own recording state (for responding to watch queries)
    private(set) var phoneIsRecording = false
    private(set) var phoneRecordingStartTime: Date?

    // Signal when watch requests phone to stop recording
    let stopRequestReceived = PassthroughSubject<Void, Never>()

    private let storageService = StorageService.shared

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
        /// Watch-side timing, missing from older watch builds.
        var firstSentAt: Date?
        var sentAt: Date?
        var attempt: Int?
    }

    /// When the watch last woke Ramble with a "wake" message. Lets the
    /// activity log say whether a recording came in because of one.
    private var lastWatchWakeAt: Date?

    // MARK: - Recording State Sync

    func sendRecordingStarted() {
        phoneIsRecording = true
        phoneRecordingStartTime = Date()
        let message: [String: Any] = [
            "type": "recordingStarted",
            "device": "phone",
            "startTime": phoneRecordingStartTime!.timeIntervalSince1970
        ]
        sendMessage(message)
    }

    func sendRecordingStopped() {
        phoneIsRecording = false
        phoneRecordingStartTime = nil
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
            try? WCSession.default.updateApplicationContext(message)
        }
    }

    // MARK: - Receipts

    /// Tells the watch this recording is saved here, so it can delete its
    /// copy. Queued user info reaches the watch even if its app is asleep.
    func sendReceipt(for recordingId: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "type": "received",
            "recordingIds": [recordingId.uuidString],
        ])
    }

    /// Debug: make the watch's stuck-note alert use seconds instead of hours.
    func sendAlertFastMode(_ enabled: Bool) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "type": "settings",
            "deliveryAlertsFastMode": enabled,
        ])
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

            case "stateQuery":
                self.respondWithCurrentState()

            default:
                break
            }
        }
    }

    // MARK: - Delivery timeline

    /// The per-hop log for a recording that just arrived from the watch:
    /// recorded → watch started sending → reached this phone, with the
    /// phone's lock and app state at arrival. Transcription and relay steps
    /// add their own entries after this, so the whole path reads in order.
    private func arrivalLog(for metadata: RecordingMetadata, receivedAt: Date) -> [ActivityEntry] {
        let savedAt = metadata.createdAt.addingTimeInterval(metadata.duration)
        var log = [ActivityEntry("Recorded on Apple Watch", at: metadata.createdAt)]

        if let firstSentAt = metadata.firstSentAt {
            log.append(ActivityEntry(
                "Watch started sending, \(DateFormatters.formatGap(from: savedAt, to: firstSentAt)) after it was recorded",
                at: firstSentAt
            ))
        }
        if let sentAt = metadata.sentAt, let attempt = metadata.attempt, attempt > 1 {
            log.append(ActivityEntry("Watch sent it again (try \(attempt))", at: sentAt))
        }

        var arrival = "Reached iPhone, \(DateFormatters.formatGap(from: savedAt, to: receivedAt)) after it was recorded"
        if let sentAt = metadata.sentAt {
            arrival += " and \(DateFormatters.formatGap(from: sentAt, to: receivedAt)) after the watch sent it"
        }
        log.append(ActivityEntry(arrival + " (\(arrivalContext(receivedAt: receivedAt)))", at: receivedAt))
        return log
    }

    /// "iPhone locked, Ramble in background, woken by the watch"
    private func arrivalContext(receivedAt: Date) -> String {
        let app = UIApplication.shared
        var parts = [
            app.isProtectedDataAvailable ? "iPhone unlocked" : "iPhone locked",
            app.applicationState == .active ? "Ramble open" : "Ramble in background",
        ]
        if let lastWatchWakeAt, receivedAt.timeIntervalSince(lastWatchWakeAt) < 60 {
            parts.append("woken by the watch")
        }
        return parts.joined(separator: ", ")
    }

    private func respondWithCurrentState() {
        var message: [String: Any] = [
            "type": "stateResponse",
            "isRecording": phoneIsRecording
        ]
        if let startTime = phoneRecordingStartTime {
            message["startTime"] = startTime.timeIntervalSince1970
        }
        sendMessage(message)
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
            return
        }
        print("Phone WCSession activated: \(activationState.rawValue)")

        if activationState == .activated {
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                handleReceivedMessage(context)
            }
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

    /// The watch's "wake" message. Sending it launches Ramble here in the
    /// background, which is the point: WatchConnectivity then hands over any
    /// files it was holding. The reply lists which of the watch's waiting
    /// recordings are already saved here, so the watch can free them now.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["type"] as? String == "wake" else {
            replyHandler([:])
            handleReceivedMessage(message)
            return
        }
        let asked = Set((message["recordingIds"] as? [String]) ?? [])
        let saved = storageService.loadRecordings()
            .map(\.id.uuidString)
            .filter { asked.contains($0) }
        replyHandler(["type": "received", "recordingIds": saved])
        Task { @MainActor in
            self.lastWatchWakeAt = Date()
            // Stay up long enough for the file to land, then transcribe and
            // send it before iOS suspends Ramble again.
            BackgroundTaskService.shared.beginImmediateBackgroundProcessing(keepAliveFor: 25)
        }
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

            let receivedAt = Date()

            Task { @MainActor in
                var recording = Recording(
                    id: UUID(uuidString: metadata.recordingId) ?? UUID(),
                    createdAt: metadata.createdAt,
                    duration: metadata.duration,
                    audioFileName: audioFileName
                )
                recording.receivedAt = receivedAt
                recording.activityLog = self.arrivalLog(for: metadata, receivedAt: receivedAt)

                let isNew = storageService.addRecording(recording)
                // Confirm only what's really on disk. Before the first unlock
                // after a restart, saving fails quietly; no receipt then
                // means the watch keeps its copy and sends it again later.
                let saved = storageService.loadRecordings().first(where: { $0.id == recording.id })
                if saved != nil {
                    self.sendReceipt(for: recording.id)
                }
                if !isNew, var existing = saved {
                    // A resend of something already here means a receipt
                    // went missing. Worth seeing when chasing a delay.
                    existing.activityLog.append(ActivityEntry(
                        "Watch sent it again\(metadata.attempt.map { " (try \($0))" } ?? ""); already saved, receipt resent"
                    ))
                    storageService.updateRecording(existing)
                }
                guard isNew else { return }
                TranscriptionQueueService.shared.enqueue(recordingId: recording.id)
                // Often arrives with the phone locked in a pocket and Ramble in
                // the background. Ask for time to transcribe and send it now,
                // and keep a deferred task as a fallback if that runs out.
                BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
                BackgroundTaskService.shared.scheduleSyncTask()
            }

            print("Received recording from watch: \(metadata.recordingId)")

        } catch {
            print("Failed to save watch recording: \(error)")
        }
    }
}
