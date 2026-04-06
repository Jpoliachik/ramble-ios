//
//  WebhookJob.swift
//  Ramble
//

import Foundation

struct WebhookJob: Identifiable, Codable {
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

    static let maxRetries = 3

    /// Backoff: 5s, 30s, 120s
    var retryDelaySeconds: TimeInterval {
        let schedule: [TimeInterval] = [5, 30, 120]
        if retryCount < schedule.count {
            return schedule[retryCount]
        }
        return 120
    }
}
