//
//  WatchConnectivityService.swift
//  watch Watch App
//
//  The watch <-> iPhone link. Notes no longer travel to the server through
//  the phone: the watch uploads them itself (WatchRelayService). What's
//  left here, per the WatchConnectivity contract:
//
//  Phone -> watch
//  - Application context: watchToken, relayBaseURL, unlocked (latest wins).
//  - ["type": "unlocked"] user info, to release held notes in the background.
//  - ["type": "received", "recordingIds": [...]] receipts for saved audio.
//  - ["type": "requestAudio", "recordingId": ...] when "Audio on watch" is tapped.
//
//  Watch -> phone
//  - ["type": "note", ...] details at stop and on each hold change.
//  - ["type": "needsConnection", "replaces": ...] when there's no working token.
//  - The audio itself, by transferFile, for playback in history.
//

import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// The application context, read off the main actor.
nonisolated struct PhoneContext: Sendable {
    let watchToken: String?
    let relayBaseURL: String?
    let unlocked: Bool

    init?(_ context: [String: Any]) {
        guard !context.isEmpty else { return nil }
        watchToken = context["watchToken"] as? String
        relayBaseURL = context["relayBaseURL"] as? String
        unlocked = context["unlocked"] as? Bool ?? false
    }
}

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published private(set) var isPhoneReachable = false
    /// False when the paired iPhone doesn't have Ramble. Starts true so the
    /// alert doesn't flash at launch.
    @Published private(set) var isCompanionAppInstalled = true

    private var lastNeedsConnectionAt: Date?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private var isActivated: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
    }

    // MARK: - Watch -> phone

    /// The note's ID, recorded time, length and hold state. Sent at the stop
    /// and whenever a hold starts or ends, so the phone's list matches.
    func sendNoteDetails(_ note: WatchNoteRecord) {
        guard isActivated else { return }
        var payload: [String: Any] = [
            "type": "note",
            "id": note.id.uuidString.uppercased(),
            "recordedAt": note.recordedAtText,
            "duration": note.duration,
            "hold": note.holdValue
        ]
        if let reason = note.refusedReason {
            payload["refusedReason"] = reason
        }
        Self.deliver(payload)
    }

    /// Asks the phone to mint a watch token. Sent when the app opens without
    /// a working token and after a 401. The phone answers by updating the
    /// application context.
    func sendNeedsConnection(replaces token: String?) {
        guard isActivated else { return }
        let session = WCSession.default
        let now = Date()
        if let lastNeedsConnectionAt, now.timeIntervalSince(lastNeedsConnectionAt) < 30 { return }
        // One queued request is enough while the phone is away
        let alreadyQueued = session.outstandingUserInfoTransfers.contains {
            $0.isTransferring && $0.userInfo["type"] as? String == "needsConnection"
        }
        if alreadyQueued && !session.isReachable { return }
        lastNeedsConnectionAt = now
        var payload: [String: Any] = ["type": "needsConnection"]
        if let token { payload["replaces"] = token }
        Self.deliver(payload)
    }

    /// sendMessage wakes the phone app in the background when it's in reach;
    /// queued user info is the fallback that arrives later.
    private nonisolated static func deliver(_ payload: [String: Any]) {
        let session = WCSession.default
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: nil) { error in
            print("Message to iPhone failed, queuing it instead: \(error)")
            WCSession.default.transferUserInfo(payload)
        }
    }

    // MARK: - Audio for the phone's history

    /// Queues the note's audio for the phone, unless it's already queued or
    /// the phone has it. The watch keeps its copy until the receipt.
    func sendAudio(_ note: WatchNoteRecord) {
        guard isActivated, !note.phoneHasAudio, !note.audioDeleted,
              FileManager.default.fileExists(atPath: note.fileURL.path)
        else { return }
        let id = note.id
        let alreadyQueued = WCSession.default.outstandingFileTransfers.contains {
            $0.isTransferring && Self.recordingId(for: $0) == id
        }
        guard !alreadyQueued else { return }

        let metadata: [String: Any] = [
            "id": id.uuidString.uppercased(),
            "recordedAt": note.recordedAtText,
            "duration": note.duration
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata),
              let text = String(data: data, encoding: .utf8)
        else { return }
        WCSession.default.transferFile(note.fileURL, metadata: ["recording": text])
    }

    /// Each time the app opens: any audio the phone hasn't confirmed.
    func resendUnconfirmedAudio() {
        for note in WatchNoteStore.shared.notes.reversed() where !note.phoneHasAudio && !note.audioDeleted {
            sendAudio(note)
        }
    }

    func cancelAudioTransfers(for id: UUID) {
        guard isActivated else { return }
        for transfer in WCSession.default.outstandingFileTransfers where Self.recordingId(for: transfer) == id {
            transfer.cancel()
        }
    }

    private nonisolated static func recordingId(for transfer: WCSessionFileTransfer) -> UUID? {
        guard let text = transfer.file.metadata?["recording"] as? String,
              let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = object["id"] as? String
        else { return nil }
        return UUID(uuidString: id)
    }

    // MARK: - Phone -> watch

    private func apply(_ context: PhoneContext) {
        let connection = WatchConnection.shared
        connection.setBaseURL(context.relayBaseURL)
        let tokenChanged = connection.setToken(context.watchToken)
        let becameUnlocked = connection.setUnlocked(context.unlocked)
        if tokenChanged && connection.token != nil {
            WatchRelayService.shared.connectionReplaced()
        } else if becameUnlocked {
            WatchRelayService.shared.accountUnlocked()
        }
    }

    /// The phone saved this audio. Only now, once the note is also final,
    /// can the watch copy go (WatchRelayService.cleanUp).
    private func handleReceipts(_ ids: [String]) {
        let store = WatchNoteStore.shared
        for id in ids.compactMap(UUID.init(uuidString:)) {
            guard store.note(id) != nil else { continue }
            cancelAudioTransfers(for: id)
            store.update(id) { $0.phoneHasAudio = true }
        }
        WatchRelayService.shared.cleanUp()
    }

    private func handleAudioRequest(_ idText: String) {
        guard let id = UUID(uuidString: idText), let note = WatchNoteStore.shared.note(id) else { return }
        sendAudio(note)
    }

    private func handle(type: String?, ids: [String]?, recordingId: String?) {
        switch type {
        case "received":
            if let ids { handleReceipts(ids) }
        case "requestAudio":
            if let recordingId { handleAudioRequest(recordingId) }
        case "unlocked":
            WatchConnection.shared.setUnlocked(true)
            WatchRelayService.shared.accountUnlocked()
        default:
            // Anything about the phone's own recording state is ignored on
            // purpose, so a tap on the watch always records.
            break
        }
    }

    /// For the watchConnectivity background task: give WatchConnectivity
    /// time to deliver what arrived while the app was asleep.
    func waitForPendingContent() async {
        guard WCSession.isSupported() else { return }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              WCSession.default.activationState != .activated || WCSession.default.hasContentPending {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Uploads released by an unlock start from here
        await WatchRelayService.shared.retryPass(force: true)
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
        let context = PhoneContext(session.receivedApplicationContext)
        Task { @MainActor in
            self.isPhoneReachable = reachable
            self.isCompanionAppInstalled = installed
            if let context { self.apply(context) }
            // Launch-time sends ran before activation finished and were
            // skipped, so catch up now.
            if WKApplication.shared().applicationState == .active {
                if !WatchConnection.shared.isConnected {
                    self.sendNeedsConnection(replaces: WatchConnection.shared.tokenToReplace)
                }
                self.resendUnconfirmedAudio()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            let becameReachable = reachable && !self.isPhoneReachable
            self.isPhoneReachable = reachable
            if becameReachable, !WatchConnection.shared.isConnected,
               WKApplication.shared().applicationState == .active {
                self.sendNeedsConnection(replaces: WatchConnection.shared.tokenToReplace)
            }
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in
            self.isCompanionAppInstalled = installed
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let context = PhoneContext(applicationContext) else { return }
        Task { @MainActor in
            self.apply(context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = message["type"] as? String
        let ids = message["recordingIds"] as? [String]
        let recordingId = message["recordingId"] as? String
        Task { @MainActor in
            self.handle(type: type, ids: ids, recordingId: recordingId)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let type = message["type"] as? String
        let ids = message["recordingIds"] as? [String]
        let recordingId = message["recordingId"] as? String
        replyHandler(["ok": true])
        Task { @MainActor in
            self.handle(type: type, ids: ids, recordingId: recordingId)
        }
    }

    /// Queued user info arrives even if the watch app wasn't running.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let type = userInfo["type"] as? String
        let ids = userInfo["recordingIds"] as? [String]
        let recordingId = userInfo["recordingId"] as? String
        Task { @MainActor in
            self.handle(type: type, ids: ids, recordingId: recordingId)
        }
    }

    /// A failed audio transfer is sent again the next time the app opens.
    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        if let error {
            print("Audio transfer to iPhone failed, will resend on next open: \(error)")
        }
    }
}
