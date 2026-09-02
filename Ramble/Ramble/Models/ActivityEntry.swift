//
//  ActivityEntry.swift
//  Ramble
//

import Foundation

struct ActivityEntry: Codable, Hashable {
    let timestamp: Date
    let message: String
    let httpStatus: Int?

    /// `timestamp` defaults to now. Pass it explicitly when logging something that
    /// happened earlier than the moment the entry is written, such as a watch
    /// recording whose file only reaches the phone later.
    init(_ message: String, httpStatus: Int? = nil, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.message = message
        self.httpStatus = httpStatus
    }
}
