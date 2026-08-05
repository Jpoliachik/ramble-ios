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

        /// Maximum audio length for a single cloud upload (20 minutes).
        /// OpenAI caps one request at 25 minutes of audio, and at 16 kHz mono
        /// AAC that limit arrives long before the 24 MB one — 24 MB is roughly
        /// an hour and a half of speech. Recordings past this are split.
        static let maxSingleUploadDuration: Double = 1200

        /// Duration per chunk when splitting large audio files (20 minutes).
        /// Must stay at or below `maxSingleUploadDuration` — a chunk is itself a
        /// single upload, so a larger value here would produce chunks the
        /// providers reject.
        static let chunkDurationSeconds: Double = 1200
    }
}
