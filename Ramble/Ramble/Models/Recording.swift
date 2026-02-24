//
//  Recording.swift
//  Ramble
//

import Foundation

enum RecordingStatus: String, Codable {
    case recorded
    case uploading
    case processing
    case completed
    case failed
}

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var status: RecordingStatus
    var transcription: String?
    var agentNotes: String?
    var lastError: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        status: RecordingStatus = .recorded,
        transcription: String? = nil,
        agentNotes: String? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.status = status
        self.transcription = transcription
        self.agentNotes = agentNotes
        self.lastError = lastError
    }

    // Backward-compatible decoder: handles old TranscriptionStatus field names
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
        agentNotes = try container.decodeIfPresent(String.self, forKey: .agentNotes)

        // New status field, or migrate from old transcriptionStatus
        if let newStatus = try? container.decode(RecordingStatus.self, forKey: .status) {
            status = newStatus
        } else if let oldStatusString = try? container.decode(String.self, forKey: .transcriptionStatus) {
            // Map old TranscriptionStatus values to new RecordingStatus
            switch oldStatusString {
            case "pending": status = .recorded
            case "uploading": status = .uploading
            case "processing": status = .processing
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

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, duration, audioFileName
        case status
        case transcription, agentNotes, lastError
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
        try container.encodeIfPresent(agentNotes, forKey: .agentNotes)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }
}
