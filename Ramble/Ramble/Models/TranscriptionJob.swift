//
//  TranscriptionJob.swift
//  Ramble
//

import Foundation

struct TranscriptionJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    var retryCount: Int
    let createdAt: Date

    init(recordingId: UUID) {
        self.id = UUID()
        self.recordingId = recordingId
        self.retryCount = 0
        self.createdAt = Date()
    }

    static let maxRetries = 3
}
