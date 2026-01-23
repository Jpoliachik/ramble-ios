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

    static let maxRetries = 5

    /// Calculates delay in nanoseconds using exponential backoff
    /// Retry 1: 5s, Retry 2: 15s, Retry 3: 45s, Retry 4: 90s, Retry 5: 180s
    var retryDelayNanoseconds: UInt64 {
        let baseDelay: UInt64 = 5_000_000_000 // 5 seconds
        let multiplier = UInt64(pow(Double(3), Double(retryCount)))
        let maxDelay: UInt64 = 180_000_000_000 // Cap at 3 minutes
        return min(baseDelay * multiplier, maxDelay)
    }
}
