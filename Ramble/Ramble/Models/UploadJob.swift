//
//  UploadJob.swift
//  Ramble
//

import Foundation

struct UploadJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    var phase: Phase
    var retryCount: Int
    let createdAt: Date
    var nextRetryAt: Date?

    enum Phase: String, Codable {
        case upload
        case poll
    }

    init(recordingId: UUID) {
        self.id = UUID()
        self.recordingId = recordingId
        self.phase = .upload
        self.retryCount = 0
        self.createdAt = Date()
        self.nextRetryAt = nil
    }

    // MARK: - Upload Phase Retry

    static let maxUploadRetries = 5

    /// Upload backoff: 5s, 15s, 45s, 90s, 180s
    var uploadRetryDelaySeconds: TimeInterval {
        let baseDelay: TimeInterval = 5
        let multiplier = pow(Double(3), Double(retryCount))
        return min(baseDelay * multiplier, 180)
    }

    // MARK: - Poll Phase Retry

    static let maxPollRetries = 20

    /// Poll schedule: 3s, 5s, 10s, 15s, 30s, then 30s thereafter
    var pollRetryDelaySeconds: TimeInterval {
        let schedule: [TimeInterval] = [3, 5, 10, 15, 30]
        if retryCount < schedule.count {
            return schedule[retryCount]
        }
        return 30
    }

    var retryDelaySeconds: TimeInterval {
        switch phase {
        case .upload: return uploadRetryDelaySeconds
        case .poll: return pollRetryDelaySeconds
        }
    }

    var maxRetries: Int {
        switch phase {
        case .upload: return Self.maxUploadRetries
        case .poll: return Self.maxPollRetries
        }
    }
}
