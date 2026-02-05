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
    var nextRetryAt: Date?

    init(recordingId: UUID) {
        self.id = UUID()
        self.recordingId = recordingId
        self.retryCount = 0
        self.createdAt = Date()
        self.nextRetryAt = nil
    }

    static let maxRetries = 5

    /// Calculates delay in seconds using exponential backoff
    /// Retry 1: 5s, Retry 2: 15s, Retry 3: 45s, Retry 4: 90s, Retry 5: 180s
    var retryDelaySeconds: TimeInterval {
        let baseDelay: TimeInterval = 5
        let multiplier = pow(Double(3), Double(retryCount))
        return min(baseDelay * multiplier, 180)
    }

    var retryDelayNanoseconds: UInt64 {
        UInt64(retryDelaySeconds * 1_000_000_000)
    }
}
