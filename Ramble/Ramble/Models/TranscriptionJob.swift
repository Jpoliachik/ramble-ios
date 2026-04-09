//
//  TranscriptionJob.swift
//  Ramble
//

import Foundation

struct TranscriptionJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    let provider: TranscriptionProvider
    let cloudModel: CloudModel?
    let customEndpointURL: String?
    let customEndpointAuthHeader: String?
    var retryCount: Int
    let createdAt: Date
    var nextRetryAt: Date?

    init(
        recordingId: UUID,
        provider: TranscriptionProvider,
        cloudModel: CloudModel? = nil,
        customEndpointURL: String? = nil,
        customEndpointAuthHeader: String? = nil
    ) {
        self.id = UUID()
        self.recordingId = recordingId
        self.provider = provider
        self.cloudModel = cloudModel
        self.customEndpointURL = customEndpointURL
        self.customEndpointAuthHeader = customEndpointAuthHeader
        self.retryCount = 0
        self.createdAt = Date()
        self.nextRetryAt = nil
    }

    /// Human-readable label for the transcription source
    var sourceLabel: String {
        provider.sourceLabel(customURL: customEndpointURL, cloudModel: cloudModel)
    }

    static let maxRetries = 5

    /// Backoff: 5s, 15s, 45s, 90s, 180s
    var retryDelaySeconds: TimeInterval {
        let baseDelay: TimeInterval = 5
        let multiplier = pow(Double(3), Double(retryCount))
        return min(baseDelay * multiplier, 180)
    }
}
