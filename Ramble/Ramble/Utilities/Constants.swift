//
//  Constants.swift
//  Ramble
//

import Foundation

enum Constants {
    /// Path appended to the API base URL for recordings
    static let recordingsPath = "ramble/recordings"

    enum AudioSettings {
        static let sampleRate: Double = 16000
        static let numberOfChannels: Int = 1
    }
}
