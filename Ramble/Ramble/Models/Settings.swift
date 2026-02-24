//
//  Settings.swift
//  Ramble
//

import Foundation

struct Settings: Codable {
    var apiBaseURL: String?
    var apiToken: String?

    init(
        apiBaseURL: String? = nil,
        apiToken: String? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.apiToken = apiToken
    }

    // Backward-compatible decoder: reads old "webhookURL"/"webhookAuthToken" keys if present
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL)
            ?? container.decodeIfPresent(String.self, forKey: .webhookURL)
        apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken)
            ?? container.decodeIfPresent(String.self, forKey: .webhookAuthToken)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(apiBaseURL, forKey: .apiBaseURL)
        try container.encodeIfPresent(apiToken, forKey: .apiToken)
    }

    static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL
        case apiToken
        case webhookURL          // legacy key for migration
        case webhookAuthToken    // legacy key for migration
    }
}
