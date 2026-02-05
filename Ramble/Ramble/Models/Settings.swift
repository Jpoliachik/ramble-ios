//
//  Settings.swift
//  Ramble
//

import Foundation

struct Settings: Codable {
    var webhookURL: String?
    var webhookAuthToken: String?
    var transcriptionQualityThreshold: Double

    init(
        webhookURL: String? = nil,
        webhookAuthToken: String? = nil,
        transcriptionQualityThreshold: Double = 0.6
    ) {
        self.webhookURL = webhookURL
        self.webhookAuthToken = webhookAuthToken
        self.transcriptionQualityThreshold = transcriptionQualityThreshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        webhookURL = try container.decodeIfPresent(String.self, forKey: .webhookURL)
        webhookAuthToken = try container.decodeIfPresent(String.self, forKey: .webhookAuthToken)
        transcriptionQualityThreshold = try container.decodeIfPresent(Double.self, forKey: .transcriptionQualityThreshold) ?? 0.6
    }

    static let `default` = Settings()
}
