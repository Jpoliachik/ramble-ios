//
//  Constants.swift
//  Ramble
//

import Foundation

enum Constants {
    enum AudioSettings {
        static let sampleRate: Double = 16000
        static let numberOfChannels: Int = 1
    }

    enum Recording {
        /// Duration threshold for a soft "long recording" warning (30 minutes)
        static let longWarningDuration: TimeInterval = 30 * 60
    }

    enum Transcription {
        /// Maximum file size for a single cloud upload (24 MB, under Whisper's 25 MB limit)
        static let maxSingleUploadSize = 24 * 1024 * 1024

        /// Duration per chunk when splitting large audio files (20 minutes)
        static let chunkDurationSeconds: Double = 1200
    }
}
