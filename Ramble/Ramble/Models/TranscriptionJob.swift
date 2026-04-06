//
//  TranscriptionJob.swift
//  Ramble
//

import Foundation

struct TranscriptionJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    let provider: TranscriptionProvider
    var retryCount: Int
    let createdAt: Date
    var nextRetryAt: Date?

    init(recordingId: UUID, provider: TranscriptionProvider) {
        self.id = UUID()
        self.recordingId = recordingId
        self.provider = provider
        self.retryCount = 0
        self.createdAt = Date()
        self.nextRetryAt = nil
    }

    static let maxRetries = 5

    /// Backoff: 5s, 15s, 45s, 90s, 180s
    var retryDelaySeconds: TimeInterval {
        let baseDelay: TimeInterval = 5
        let multiplier = pow(Double(3), Double(retryCount))
        return min(baseDelay * multiplier, 180)
    }
}
