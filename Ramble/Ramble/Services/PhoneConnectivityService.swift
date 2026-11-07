//
//  PhoneConnectivityService.swift
//  Ramble
//
//  The WatchConnectivity side of the phone. The watch uploads its own notes
//  straight to Ramble's server; this carries what the phone gives the watch
//  (its token, the relay address, the unlock) and what the watch tells the
//  phone (note details and holds, "needs a connection", audio for playback).
//  Message shapes: the WatchConnectivity contract in the redesign build
//  notes; Apple API choices: docs/sync-architecture.md.
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

    private static let watchTokenKey = "watchToken"
    /// Identifies the paired watch: WatchConnectivity gives each paired
    /// watch its own directory.
    private static let pairedWatchKey = "pairedWatchDirectory"

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Recording State Sync

    func sendRecordingStarted() {
        phoneIsRecording = true
        let start = Date()
        phoneRecordingStartTime = start
        sendMessage([
            "type": "recordingStarted",
            "device": "phone",
            "startTime": start.timeIntervalSince1970,
        ])
    }

    func sendRecordingStopped() {
        phoneIsRecording = false
        phoneRecordingStartTime = nil
        sendMessage(["type": "recordingStopped", "device": "phone"])
    }

    func requestWatchStopRecording() {
        sendMessage(["type": "stopRequest"])
    }

    /// Live state only matters while the watch is reachable. Never falls
    /// back to the application context, which carries the watch's token.
    private func sendMessage(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send message: \(error)")
        }
    }

    // MARK: - Connecting the watch

    /// Gives the watch a token if it needs one (or always, with `force`),
    /// then sends the application context. Only after consent.
    @MainActor
    func connectWatch(force: Bool, replaces: String?) async {
        guard Consent.hasConsented, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        let current = KeychainService.string(forKey: Self.watchTokenKey)
        if current != nil && !force {
            pushApplicationContext()
            return
        }
        guard !KeychainService.isLocked else { return }
        do {
            let token = try await RelayService.shared.mintWatchToken(replaces: replaces ?? current)
            KeychainService.setString(token, forKey: Self.watchTokenKey)
            pushApplicationContext()
        } catch {
            print("Couldn't connect the watch: \(error.localizedDescription)")
        }
    }

    /// The watch says it has no working token. Mints only when the token
    /// it gave up on is the phone's current one (the server refused it),
    /// the phone has none, or a different watch is paired. Otherwise the
    /// watch just missed the current token, so it's sent again: minting
    /// would replace a working token, fail the watch's in-flight uploads
    /// and use up the server's daily limit.
    @MainActor
    private func answerNeedsConnection(replaces: String?) async {
        let current = KeychainService.string(forKey: Self.watchTokenKey)
        var watchChanged = false
        if let directory = WCSession.default.watchDirectoryURL?.path {
            let previous = UserDefaults.standard.string(forKey: Self.pairedWatchKey)
            watchChanged = previous != nil && previous != directory
            UserDefaults.standard.set(directory, forKey: Self.pairedWatchKey)
        }
        let refused = replaces != nil && replaces == current
        await connectWatch(force: current == nil || refused || watchChanged, replaces: replaces)
    }

    /// Latest wins; sent again on every change. `sentAt` makes each context
    /// differ, so WatchConnectivity delivers a re-sent token too.
    @MainActor
    func pushApplicationContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired else { return }
        // Before the first unlock after a restart the token can't be read;
        // a context without it would tell the watch it isn't connected.
        guard !KeychainService.isLocked else { return }
        var context: [String: Any] = [
            "relayBaseURL": Constants.Relay.baseURL.absoluteString,
            "unlocked": AccountService.shared.isUnlocked,
            "deliveryAlertsFastMode": DeliveryMonitor.isFastMode,
            "sentAt": Date().ISO8601Format(),
        ]
        if Consent.hasConsented, let token = KeychainService.string(forKey: Self.watchTokenKey) {
            context["watchToken"] = token
        }
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("Couldn't update the watch's context: \(error)")
        }
    }

    /// Lets the watch release held notes in the background.
    @MainActor
    func sendUnlocked() {
        guard WCSession.default.activationState == .activated, WCSession.default.isPaired else { return }
        WCSession.default.transferUserInfo(["type": "unlocked"])
    }

    /// Re-mints when a different watch is now paired with this phone.
    @MainActor
    private func checkPairedWatch() async {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired,
              let directory = session.watchDirectoryURL?.path else { return }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Self.pairedWatchKey)
        defaults.set(directory, forKey: Self.pairedWatchKey)
        await connectWatch(force: previous != nil && previous != directory, replaces: nil)
    }

    // MARK: - Audio for playback

    /// Asks the watch for a note's audio. False when the watch app isn't
    /// open, which the phone can't change ("Open Ramble on your watch to sync.").
    @MainActor
    func requestAudio(for recordingId: UUID) -> Bool {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return false }
        session.sendMessage(["type": "requestAudio", "recordingId": recordingId.uuidString], replyHandler: nil) { error in
            print("Audio request failed: \(error)")
        }
        return true
    }

    // MARK: - Receipts

    /// Tells the watch this note's audio is saved here, so it can delete its
    /// copy once the transcript is done. Queued user info reaches the watch
    /// even if its app is asleep.
    func sendReceipt(for recordingIds: [UUID]) {
        guard !recordingIds.isEmpty, WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = ["type": "received", "recordingIds": recordingIds.map(\.uuidString)]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - Incoming

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

            case "note":
                self.handleNoteDetails(message)
                self.wakeCheckIn()

            case "needsConnection":
                BackgroundTaskService.shared.beginImmediateBackgroundProcessing(keepAliveFor: 20)
                await self.answerNeedsConnection(replaces: message["replaces"] as? String)

            default:
                break
            }
        }
    }

    /// A watch note's details and hold state. The server's word wins once
    /// it has accepted the note; until then the watch's hold shows.
    @MainActor
    private func handleNoteDetails(_ message: [String: Any]) {
        guard let idString = message["id"] as? String, let id = UUID(uuidString: idString),
              !storageService.isDeleted(id) else { return }
        let recordedAt = (message["recordedAt"] as? String).flatMap(RelayService.parseDate) ?? Date()
        let duration = (message["duration"] as? Double) ?? 0

        if storageService.recording(withId: id) == nil {
            var recording = Recording(id: id, createdAt: recordedAt, duration: duration, source: .watch)
            recording.activityLog.append(ActivityEntry("Recorded on Apple Watch", at: recordedAt))
            storageService.addRecording(recording)
        }

        let hold: NoteHold?
        switch message["hold"] as? String {
        case "unlock": hold = .unlock
        case "fairUse": hold = .fairUse
        case "refused": hold = (message["refusedReason"] as? String) == "too_long" ? .tooLong : .couldntSend
        default: hold = nil
        }
        storageService.update(id) { r in
            if r.duration == 0 { r.duration = duration }
            guard r.status == .recorded, r.hold != hold else { return }
            r.hold = hold
            switch hold {
            case .unlock: r.activityLog.append(ActivityEntry("Held on the watch until Ramble is unlocked"))
            case .fairUse: r.activityLog.append(ActivityEntry("Held on the watch: usage limit reached"))
            case .tooLong, .couldntSend: r.activityLog.append(ActivityEntry("Refused by Ramble's server"))
            case nil: r.activityLog.append(ActivityEntry("Sending from the watch"))
            }
        }
    }

    /// Any message from the watch is a chance to collect transcripts.
    @MainActor
    private func wakeCheckIn() {
        BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
    }

    /// For background launches: wait (up to 8s) for the session to activate
    /// and for WatchConnectivity to deliver anything it queued while Ramble
    /// wasn't running.
    func waitForPendingWatchContent() async {
        guard WCSession.isSupported() else { return }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline,
              WCSession.default.activationState != .activated || WCSession.default.hasContentPending {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func respondWithCurrentState() {
        var message: [String: Any] = [
            "type": "stateResponse",
            "isRecording": phoneIsRecording,
        ]
        if let startTime = phoneRecordingStartTime {
            message["startTime"] = startTime.timeIntervalSince1970
        }
        sendMessage(message)
    }

    // MARK: - Audio files

    /// `["recording": <JSON of {id, recordedAt, duration}>]`.
    fileprivate struct AudioMetadata {
        let id: UUID
        let recordedAt: Date
        let duration: TimeInterval

        init?(json data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idString = object["id"] as? String,
                  let id = UUID(uuidString: idString) else { return nil }
            self.id = id
            recordedAt = (object["recordedAt"] as? String).flatMap(RelayService.parseDate) ?? Date()
            duration = (object["duration"] as? Double) ?? 0
        }
    }

    /// Saves a watch note's audio that arrived by file transfer or message.
    /// `writeAudio` runs synchronously before this returns; `onSaved` gets
    /// whether the audio is on disk here (and so was receipted).
    fileprivate func ingest(
        _ metadata: AudioMetadata,
        via path: String,
        writeAudio: (URL) throws -> Void,
        onSaved: ((Bool) -> Void)? = nil
    ) {
        let id = metadata.id
        // Deleted here: the watch can let go, but the note stays gone.
        if storageService.isDeleted(id) {
            sendReceipt(for: [id])
            onSaved?(true)
            return
        }
        let destinationURL = StorageService.audioDirectory.appendingPathComponent("\(id.uuidString).m4a")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            sendReceipt(for: [id])
            onSaved?(true)
            return
        }
        do {
            try writeAudio(destinationURL)
        } catch {
            print("Failed to save watch audio: \(error)")
            onSaved?(false)
            return
        }

        let receivedAt = Date()
        Task { @MainActor in
            if self.storageService.recording(withId: id) == nil {
                var recording = Recording(id: id, createdAt: metadata.recordedAt, duration: metadata.duration, source: .watch)
                recording.activityLog.append(ActivityEntry("Recorded on Apple Watch", at: metadata.recordedAt))
                self.storageService.addRecording(recording)
            }
            let saved = self.storageService.update(id) {
                $0.receivedAt = receivedAt
                if $0.duration == 0 { $0.duration = metadata.duration }
                $0.activityLog.append(ActivityEntry("Audio reached iPhone by \(path)", at: receivedAt))
            }
            // Confirm only what's really saved. Before the first unlock after
            // a restart, saving fails quietly; the watch then sends it again.
            if saved != nil {
                self.sendReceipt(for: [id])
            }
            onSaved?(saved != nil)
            // A retry may have been waiting for this audio.
            UploadQueueService.shared.processNextIfNeeded()
            self.wakeCheckIn()
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
            return
        }
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            handleReceivedMessage(context)
        }
        Task { @MainActor in
            await self.checkPairedWatch()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A different watch was switched in; activate for it.
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            await self.checkPairedWatch()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedMessage(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler(["ok": true])
        handleReceivedMessage(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleReceivedMessage(userInfo)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        handleReceivedMessage(applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadataString = file.metadata?["recording"] as? String,
              let metadata = AudioMetadata(json: Data(metadataString.utf8))
        else {
            print("Failed to parse watch recording metadata")
            return
        }
        // Must copy before returning: WatchConnectivity deletes the file then.
        ingest(metadata, via: "file transfer") { destinationURL in
            try FileManager.default.copyItem(at: file.fileURL, to: destinationURL)
        }
    }
}
