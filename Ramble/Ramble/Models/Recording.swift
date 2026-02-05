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
    var webhookRetryCount: Int
    var nextWebhookRetryAt: Date?

    static let maxInAppWebhookRetries = 5
    static let maxTotalWebhookRetries = 15

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
        transcriptionLanguage: String? = nil,
        webhookRetryCount: Int = 0,
        nextWebhookRetryAt: Date? = nil
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
        self.webhookRetryCount = webhookRetryCount
        self.nextWebhookRetryAt = nextWebhookRetryAt
    }

    // Custom decoder to handle backward compatibility when new fields are added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
        transcriptionStatus = try container.decode(TranscriptionStatus.self, forKey: .transcriptionStatus)
        lastTranscriptionError = try container.decodeIfPresent(String.self, forKey: .lastTranscriptionError)
        webhookAttempts = try container.decodeIfPresent([WebhookAttempt].self, forKey: .webhookAttempts) ?? []
        noSpeechProbability = try container.decodeIfPresent(Double.self, forKey: .noSpeechProbability)
        transcriptionLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage)
        webhookRetryCount = try container.decodeIfPresent(Int.self, forKey: .webhookRetryCount) ?? 0
        nextWebhookRetryAt = try container.decodeIfPresent(Date.self, forKey: .nextWebhookRetryAt)
    }

    var audioFileURL: URL {
        StorageService.audioDirectory.appendingPathComponent(audioFileName)
    }

    /// Check if transcription quality is acceptable based on threshold
    func isQualityAcceptable(threshold: Double) -> Bool {
        guard let noSpeechProb = noSpeechProbability else {
            return true
        }
        return noSpeechProb < threshold
    }

    /// Whether the webhook needs an automatic retry
    var needsWebhookRetry: Bool {
        guard let retryAt = nextWebhookRetryAt else { return false }
        return webhookRetryCount < Self.maxTotalWebhookRetries && retryAt <= Date()
    }

    /// Whether all automatic webhook retries have been exhausted
    var webhookRetriesExhausted: Bool {
        let lastFailed = webhookAttempts.last.map { !$0.success } ?? false
        return lastFailed && webhookRetryCount >= Self.maxTotalWebhookRetries
    }

    /// Delay in seconds for the next webhook retry based on exponential backoff
    var webhookRetryDelaySeconds: TimeInterval {
        if webhookRetryCount < Self.maxInAppWebhookRetries {
            // In-app: 5s, 15s, 45s, 90s, 180s
            let baseDelay: TimeInterval = 5
            let multiplier = pow(Double(3), Double(webhookRetryCount))
            return min(baseDelay * multiplier, 180)
        } else {
            // Background: 5min, 10min, 15min, 30min (capped)
            let bgRetryIndex = webhookRetryCount - Self.maxInAppWebhookRetries
            let baseDelay: TimeInterval = 300 // 5 minutes
            let multiplier = Double(bgRetryIndex + 1)
            return min(baseDelay * multiplier, 1800) // cap at 30 min
        }
    }
}
