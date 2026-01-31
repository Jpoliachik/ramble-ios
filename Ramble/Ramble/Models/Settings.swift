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

    static let `default` = Settings()
}
