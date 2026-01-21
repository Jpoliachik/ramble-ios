//
//  Settings.swift
//  Ramble
//

import Foundation

struct Settings: Codable {
    var webhookURL: String?
    var webhookAuthToken: String

    init(webhookURL: String? = nil, webhookAuthToken: String? = nil) {
        self.webhookURL = webhookURL
        self.webhookAuthToken = webhookAuthToken ?? UUID().uuidString
    }

    static let `default` = Settings()
}
