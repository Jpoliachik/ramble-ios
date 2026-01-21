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

struct Recording: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var transcription: String?
    var transcriptionStatus: TranscriptionStatus

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        transcription: String? = nil,
        transcriptionStatus: TranscriptionStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName ?? "\(id.uuidString).m4a"
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
    }

    var audioFileURL: URL {
        StorageService.audioDirectory.appendingPathComponent(audioFileName)
    }
}
