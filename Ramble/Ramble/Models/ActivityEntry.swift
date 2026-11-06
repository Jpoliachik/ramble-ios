//
//  ActivityEntry.swift
//  Ramble
//

import Foundation

struct ActivityEntry: Codable, Hashable {
    let timestamp: Date
    let message: String
    let httpStatus: Int?

    /// `at` backdates the entry, for steps that happened on the watch
    /// before the recording reached this phone.
    init(_ message: String, at timestamp: Date = Date(), httpStatus: Int? = nil) {
        self.timestamp = timestamp
        self.message = message
        self.httpStatus = httpStatus
    }
}
