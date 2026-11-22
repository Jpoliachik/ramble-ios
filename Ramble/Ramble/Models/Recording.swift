//
//  Recording.swift
//  Ramble
//
//  One note in the iPhone's history, from either device. The iPhone is the
//  only full history (specs/phone.md): the server is a temporary mailbox, so
//  this row keeps the last state the phone saw even after the server forgets
//  the note.
//

import Foundation

/// Where the note is on the server, as far as the phone knows.
enum RecordingStatus: String, Codable {
    /// Not accepted by the server yet (or held, see `Recording.hold`).
    case recorded
    /// Accepted; the server is transcribing it.
    case transcribing
    /// Done: a transcript, or no speech (`Recording.noSpeech`).
    case completed
    /// Transcription failed for good ("Couldn't transcribe").
    case failed
}

enum WebhookStatus: String, Codable {
    case pending
    case sending
    case delivered
    case failed
}

enum NoteSource: String, Codable {
    case phone
    case watch
}

/// Why the server won't take this note's audio, for now or for good.
enum NoteHold: String, Codable {
    /// 402 free_notes_used: waits for the unlock.
    case unlock
    /// Final refusal: over the length or size limit.
    case tooLong
    /// Final refusal: anything else (unreadable, unsupported, suspended).
    case couldntSend
}

/// What the relay reports about a note's agent copies (POST /inbox/status).
struct AgentDelivery: Codable, Hashable {
    var copies: Int
    var waiting: Int
    var pickedUp: Int
    var removed: Int
    var firstPickedUpAt: Date?
    /// Each agent's copy, in pairing order. Nil for notes checked before
    /// the relay reported per agent.
    var agents: [AgentCopy]? = nil

    /// "Your agent has it", or "Your agents have it" / "2 of 3 agents have it".
    var hasItLabel: String {
        if copies <= 1 { return "Your agent has it" }
        if pickedUp == copies { return "Your agents have it" }
        return "\(pickedUp) of \(copies) agents have it"
    }

    /// "Waiting for your agent", or "Waiting for your agents" / "Waiting for 1 of 3 agents".
    var waitingLabel: String {
        if copies <= 1 { return "Waiting for your agent" }
        if waiting == copies { return "Waiting for your agents" }
        return "Waiting for \(waiting) of \(copies) agents"
    }
}

/// One agent's copy of a note.
struct AgentCopy: Codable, Hashable {
    enum State: String, Codable {
        case waiting
        case pickedUp = "picked_up"
        case removed
    }

    var connectionId: String
    /// What the agent called itself; nil if unnamed or since disconnected.
    var name: String?
    var state: State
    var pickedUpAt: Date?
}

struct Recording: Identifiable, Codable, Hashable {
    /// Hand retries of a failed transcription, per note (relay-api.md).
    static let maxRetries = 1
    /// How long the watch keeps audio the phone never confirmed (watch.md).
    static let watchAudioRetention: TimeInterval = 30 * 24 * 3600

    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var source: NoteSource
    var status: RecordingStatus
    var transcription: String?
    /// Done with result "no_speech".
    var noSpeech: Bool
    /// For failed notes: "audio_rejected" or "retries_exhausted".
    var failureResult: String?
    var hold: NoteHold?
    /// When a hold was released (the unlock).
    var releasedAt: Date?
    /// Hand retries already accepted by the server.
    var retryCount: Int
    /// The person asked for a retry that hasn't been accepted yet.
    var retryRequested: Bool
    /// When the server accepted the audio (`received_at`).
    var acceptedAt: Date?
    /// `recorded_at` exactly as the server has it (the recording device's
    /// own string, offset included), for the webhook's note record.
    var recordedAtText: String? = nil
    /// When the note became final (done or failed), as the phone saw it.
    var finishedAt: Date?
    var webhookStatus: WebhookStatus?
    var agentDelivery: AgentDelivery?
    /// When the watch's audio reached this phone.
    var receivedAt: Date?
    var lastError: String?
    var activityLog: [ActivityEntry]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        source: NoteSource = .phone,
        status: RecordingStatus = .recorded,
        transcription: String? = nil,
        webhookStatus: WebhookStatus? = nil,
        lastError: String? = nil,
        activityLog: [ActivityEntry] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.source = source
        self.status = status
        self.transcription = transcription
        self.noSpeech = false
        self.failureResult = nil
        self.hold = nil
        self.releasedAt = nil
        self.retryCount = 0
        self.retryRequested = false
        self.acceptedAt = nil
        self.finishedAt = nil
        self.webhookStatus = webhookStatus
        self.agentDelivery = nil
        self.receivedAt = nil
        self.lastError = lastError
        self.activityLog = activityLog
    }

    // Backward-compatible decoder: old builds transcribed on the phone and
    // tracked the relay upload in relayStatus / relayUploadedAt / pickedUpAt.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        audioFileName = try c.decode(String.self, forKey: .audioFileName)
        transcription = try c.decodeIfPresent(String.self, forKey: .transcription)
        webhookStatus = try c.decodeIfPresent(WebhookStatus.self, forKey: .webhookStatus)
        receivedAt = try c.decodeIfPresent(Date.self, forKey: .receivedAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        activityLog = (try? c.decodeIfPresent([ActivityEntry].self, forKey: .activityLog)) ?? []

        // Older rows have no source: watch notes were the ones that arrived.
        let storedSource = try c.decodeIfPresent(NoteSource.self, forKey: .source)
        source = storedSource ?? (receivedAt != nil ? .watch : .phone)

        switch try c.decodeIfPresent(String.self, forKey: .status) {
        // In older builds "transcribing" meant on this phone, which the
        // server never saw, so those notes still need to be sent.
        case "transcribing": status = storedSource == nil ? .recorded : .transcribing
        case "completed": status = .completed
        case "failed": status = .failed
        default: status = .recorded
        }
        // An older build's untranscribed watch note: the watch already let
        // go of its audio, so this phone sends it like its own.
        if storedSource == nil && status == .recorded { source = .phone }

        noSpeech = try c.decodeIfPresent(Bool.self, forKey: .noSpeech) ?? false
        failureResult = try c.decodeIfPresent(String.self, forKey: .failureResult)
        // A hold an older build saved that no longer exists reads as none.
        hold = try? c.decodeIfPresent(NoteHold.self, forKey: .hold)
        releasedAt = try c.decodeIfPresent(Date.self, forKey: .releasedAt)
        retryCount = try c.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        retryRequested = try c.decodeIfPresent(Bool.self, forKey: .retryRequested) ?? false
        acceptedAt = try c.decodeIfPresent(Date.self, forKey: .acceptedAt)
        recordedAtText = try c.decodeIfPresent(String.self, forKey: .recordedAtText)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)

        if let delivery = try c.decodeIfPresent(AgentDelivery.self, forKey: .agentDelivery) {
            agentDelivery = delivery
        } else if status == .completed,
                  c.contains(.relayStatus) || (acceptedAt == nil && finishedAt == nil) {
            // A note saved by an older build: migrate its relay fields into
            // the new delivery shape. A note this build saved without a
            // delivery is still waiting for its first delivery check.
            let relayStatus = try c.decodeIfPresent(WebhookStatus.self, forKey: .relayStatus)
            let pickedUpAt = try c.decodeIfPresent(Date.self, forKey: .pickedUpAt)
            let uploadedAt = try c.decodeIfPresent(Date.self, forKey: .relayUploadedAt)
            if relayStatus == .delivered {
                agentDelivery = AgentDelivery(
                    copies: 1,
                    waiting: pickedUpAt == nil ? 1 : 0,
                    pickedUp: pickedUpAt == nil ? 0 : 1,
                    removed: 0,
                    firstPickedUpAt: pickedUpAt
                )
                if acceptedAt == nil { acceptedAt = uploadedAt }
            } else {
                agentDelivery = AgentDelivery(copies: 0, waiting: 0, pickedUp: 0, removed: 0, firstPickedUpAt: nil)
            }
        } else {
            agentDelivery = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(duration, forKey: .duration)
        try c.encode(audioFileName, forKey: .audioFileName)
        try c.encode(source, forKey: .source)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(transcription, forKey: .transcription)
        if noSpeech { try c.encode(noSpeech, forKey: .noSpeech) }
        try c.encodeIfPresent(failureResult, forKey: .failureResult)
        try c.encodeIfPresent(hold, forKey: .hold)
        try c.encodeIfPresent(releasedAt, forKey: .releasedAt)
        if retryCount > 0 { try c.encode(retryCount, forKey: .retryCount) }
        if retryRequested { try c.encode(retryRequested, forKey: .retryRequested) }
        try c.encodeIfPresent(acceptedAt, forKey: .acceptedAt)
        try c.encodeIfPresent(recordedAtText, forKey: .recordedAtText)
        try c.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try c.encodeIfPresent(webhookStatus, forKey: .webhookStatus)
        try c.encodeIfPresent(agentDelivery, forKey: .agentDelivery)
        try c.encodeIfPresent(receivedAt, forKey: .receivedAt)
        try c.encodeIfPresent(lastError, forKey: .lastError)
        if !activityLog.isEmpty { try c.encode(activityLog, forKey: .activityLog) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, duration, audioFileName, source, status, transcription
        case noSpeech, failureResult, hold, releasedAt, retryCount, retryRequested
        case acceptedAt, recordedAtText, finishedAt, webhookStatus, agentDelivery, receivedAt, lastError, activityLog
        // Legacy keys, read for migration only
        case relayStatus, relayUploadedAt, pickedUpAt
    }

    // MARK: - Derived

    var audioFileURL: URL {
        StorageService.audioDirectory.appendingPathComponent(audioFileName)
    }

    var hasAudio: Bool {
        FileManager.default.fileExists(atPath: audioFileURL.path)
    }

    /// A transcript with words in it.
    var hasSpeechTranscript: Bool {
        status == .completed && !noSpeech
            && !(transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A watch note whose audio hasn't reached this phone, while the watch
    /// still keeps it (watch.md: at most 30 days after the note is final).
    var isAudioOnWatch: Bool {
        guard source == .watch, !hasAudio else { return false }
        guard let finishedAt else { return true }
        return Date().timeIntervalSince(finishedAt) < Self.watchAudioRetention
    }

    var retriesLeft: Int { max(0, Self.maxRetries - retryCount) }

    /// "Couldn't transcribe" and the person can still retry it.
    var canRetryTranscription: Bool {
        status == .failed && hold == nil && !retryRequested && retriesLeft > 0
    }

    /// When the note's agent copies started waiting, for the 12-hour rules.
    var waitingSince: Date {
        acceptedAt ?? createdAt.addingTimeInterval(duration)
    }
}
