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

    init(url: String, success: Bool, statusCode: Int? = nil, errorMessage: String? = nil) {
        self.id = UUID()
        self.url = url
        self.timestamp = Date()
        self.success = success
        self.statusCode = statusCode
        self.errorMessage = errorMessage
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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        transcription: String? = nil,
        transcriptionStatus: TranscriptionStatus = .pending,
        lastTranscriptionError: String? = nil,
        webhookAttempts: [WebhookAttempt] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.lastTranscriptionError = lastTranscriptionError
        self.webhookAttempts = webhookAttempts
    }

    var audioFileURL: URL {
        StorageService.audioDirectory.appendingPathComponent(audioFileName)
    }
}
