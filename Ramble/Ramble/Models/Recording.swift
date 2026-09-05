//
//  Recording.swift
//  Ramble
//

import Foundation

enum RecordingStatus: String, Codable {
    case recorded
    case transcribing
    case completed
    case failed
}

enum WebhookStatus: String, Codable {
    case pending
    case sending
    case delivered
    case failed
}

/// One speaker's uninterrupted stretch of speech, as diarization saw it.
struct SpeakerTurn: Codable, Hashable {
    /// Nil when no speaker could be attributed to this stretch.
    let speaker: Int?
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// Which language decoded this turn, when known. Useful downstream: a summary
    /// of a bilingual meeting reads differently if it knows who spoke what.
    let language: String?
    /// Whisper's mean log probability for the turn. Higher is more confident, so a
    /// consumer can discount a shaky stretch rather than trusting it equally.
    let confidence: Float?
}

/// How close two speakers' voices are, so a consumer knows *which* pair might be
/// one person rather than only that some pair is.
struct SpeakerPairDistance: Codable, Hashable {
    let speakers: [Int]
    let distance: Float
}

/// What diarization concluded, kept alongside the transcript so a webhook can
/// consume the structure instead of parsing "Speaker 1:" out of prose.
struct SpeakerAnalysis: Codable, Hashable {
    let speakerCount: Int
    let turns: [SpeakerTurn]
    /// Cosine distance for every pair of speakers. Low values mean those two labels
    /// probably belong to one person, which is diarization's usual mistake. There is
    /// no universal threshold; calibrate against your own recordings.
    let pairDistances: [SpeakerPairDistance]
}

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var status: RecordingStatus
    var transcription: String?
    var webhookStatus: WebhookStatus?
    var lastError: String?
    var activityLog: [ActivityEntry]
    var cloudTranscriptionCount: Int
    var speakerAnalysis: SpeakerAnalysis?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        status: RecordingStatus = .recorded,
        transcription: String? = nil,
        webhookStatus: WebhookStatus? = nil,
        lastError: String? = nil,
        activityLog: [ActivityEntry] = [],
        cloudTranscriptionCount: Int = 0,
        speakerAnalysis: SpeakerAnalysis? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.status = status
        self.transcription = transcription
        self.webhookStatus = webhookStatus
        self.lastError = lastError
        self.activityLog = activityLog
        self.cloudTranscriptionCount = cloudTranscriptionCount
        self.speakerAnalysis = speakerAnalysis
    }

    // Backward-compatible decoder: handles old status field names and values
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
        webhookStatus = try container.decodeIfPresent(WebhookStatus.self, forKey: .webhookStatus)

        // New status field, or migrate from old transcriptionStatus/status values
        if let statusString = try? container.decode(String.self, forKey: .status) {
            switch statusString {
            case "recorded": status = .recorded
            case "transcribing": status = .transcribing
            case "completed": status = .completed
            case "failed": status = .failed
            // Map old statuses to new
            case "uploading", "processing": status = .transcribing
            default: status = .recorded
            }
        } else if let oldStatusString = try? container.decode(String.self, forKey: .transcriptionStatus) {
            switch oldStatusString {
            case "pending": status = .recorded
            case "uploading", "processing": status = .transcribing
            case "completed": status = .completed
            case "failed": status = .failed
            default: status = .recorded
            }
        } else {
            status = .recorded
        }

        // New lastError field, or migrate from old lastTranscriptionError
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
            ?? container.decodeIfPresent(String.self, forKey: .lastTranscriptionError)

        activityLog = (try? container.decodeIfPresent([ActivityEntry].self, forKey: .activityLog)) ?? []
        cloudTranscriptionCount = try container.decodeIfPresent(Int.self, forKey: .cloudTranscriptionCount) ?? 0
        speakerAnalysis = try? container.decodeIfPresent(SpeakerAnalysis.self, forKey: .speakerAnalysis)
    }

    var audioFileURL: URL {
        StorageService.audioDirectory.appendingPathComponent(audioFileName)
    }

    var isModelNotInstalled: Bool {
        status == .failed
            && lastError == SpeechAnalyzerTranscriptionService.modelNotInstalledError
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, duration, audioFileName
        case status
        case transcription, webhookStatus, lastError, activityLog, cloudTranscriptionCount
        case speakerAnalysis
        // Legacy keys for migration
        case transcriptionStatus
        case lastTranscriptionError
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(audioFileName, forKey: .audioFileName)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(transcription, forKey: .transcription)
        try container.encodeIfPresent(webhookStatus, forKey: .webhookStatus)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        if !activityLog.isEmpty {
            try container.encode(activityLog, forKey: .activityLog)
        }
        if cloudTranscriptionCount > 0 {
            try container.encode(cloudTranscriptionCount, forKey: .cloudTranscriptionCount)
        }
        try container.encodeIfPresent(speakerAnalysis, forKey: .speakerAnalysis)
    }
}
