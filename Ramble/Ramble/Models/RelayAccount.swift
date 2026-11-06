//
//  RelayAccount.swift
//  Ramble
//
//  The account state the relay reports in GET /account and POST /entitlement
//  (specs/relay-api.md "Account state"). The server decides; the app shows it.
//

import Foundation

struct RelayAccount: Codable, Equatable {
    var unlocked: Bool
    var freeNotesTotal: Int
    var freeNotesRemaining: Int
    var fairUse: RelayFairUse?
    var accountToken: String?
}

struct RelayFairUse: Codable, Equatable {
    var usedHours: Double
    var limitHours: Double
    var resetsAt: Date
}
