//
//  Recording.swift
//  Ramble
//

import Foundation

enum TranscriptionStatus: String, Codable {
    case pending
    case uploading
    case processing
    case completed
    case failed
}

struct WebhookAttempt: Codable, Hashable, Identifiable {
    let id: UUID
    let url: String
    let timestamp: Date
    let success: Bool
    let statusCode: Int?
    let errorMessage: String?
    let durationMs: Int?

    init(
        url: String,
        success: Bool,
        statusCode: Int? = nil,
        errorMessage: String? = nil,
        durationMs: Int? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.timestamp = Date()
        self.success = success
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.durationMs = durationMs
    }
}

struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var transcription: String?
    var transcriptionStatus: TranscriptionStatus
    var lastTranscriptionError: String?
    var webhookAttempts: [WebhookAttempt]
    var noSpeechProbability: Double?
    var transcriptionLanguage: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        transcription: String? = nil,
        transcriptionStatus: TranscriptionStatus = .pending,
        lastTranscriptionError: String? = nil,
        webhookAttempts: [WebhookAttempt] = [],
        noSpeechProbability: Double? = nil,
        transcriptionLanguage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.lastTranscriptionError = lastTranscriptionError
        self.webhookAttempts = webhookAttempts
        self.noSpeechProbability = noSpeechProbability
        self.transcriptionLanguage = transcriptionLanguage
    }

    var audioFileURL: URL {
        StorageService.audioDirectory.appendingPathComponent(audioFileName)
    }

    /// Check if transcription quality is acceptable based on threshold
    func isQualityAcceptable(threshold: Double) -> Bool {
        guard let noSpeechProb = noSpeechProbability else {
            // If no quality data, assume acceptable (backward compatibility)
            return true
        }
        return noSpeechProb < threshold
    }
}
