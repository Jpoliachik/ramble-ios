//
//  ActivityEntry.swift
//  Ramble
//

import Foundation

struct ActivityEntry: Codable, Hashable {
    let timestamp: Date
    let message: String
    let httpStatus: Int?

    init(_ message: String, httpStatus: Int? = nil) {
        self.timestamp = Date()
        self.message = message
        self.httpStatus = httpStatus
    }
}
