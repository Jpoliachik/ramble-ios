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

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var status: RecordingStatus
    var transcription: String?
    var webhookStatus: WebhookStatus?
    var lastError: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        status: RecordingStatus = .recorded,
        transcription: String? = nil,
        webhookStatus: WebhookStatus? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.status = status
        self.transcription = transcription
        self.webhookStatus = webhookStatus
        self.lastError = lastError
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
        case transcription, webhookStatus, lastError
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
    }
}
