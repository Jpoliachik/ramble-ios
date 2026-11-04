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

    enum Relay {
        /// The hosted Ramble Relay. It's served by the same Worker as cloud
        /// transcription (proxy/), so it shares that host and its App Attest
        /// state. Until the Worker's D1 database is set up, relay calls get a
        /// 503 and the Connect screen shows that error.
        static let hostedBaseURL = URL(string: "https://ramble-transcription-proxy.jpoliachik.workers.dev")!

        /// UserDefaults key for a developer override (Debug sheet).
        static let baseURLOverrideKey = "relayBaseURLOverride"

        /// What the relay's RETENTION_SECONDS is set to, in days. Shown in the
        /// privacy copy; keep in sync with proxy/wrangler.toml.
        static let unclaimedRetentionDays = 30

        static var baseURL: URL {
            if let override = UserDefaults.standard.string(forKey: baseURLOverrideKey),
               !override.isEmpty,
               let url = URL(string: override) {
                return url
            }
            return hostedBaseURL
        }
    }

    enum Transcription {
        /// Maximum file size for a single cloud upload (24 MB, under Whisper's 25 MB limit)
        static let maxSingleUploadSize = 24 * 1024 * 1024

        /// Maximum audio length for a single cloud upload (20 minutes).
        /// OpenAI caps one request at 25 minutes of audio, and at 16 kHz mono
        /// AAC that limit arrives long before the 24 MB one — 24 MB is roughly
        /// an hour and a half of speech. Recordings past this are split.
        static let maxSingleUploadDuration: Double = 1200

        /// Duration per chunk when splitting large audio files (20 minutes)
        static let chunkDurationSeconds: Double = 1200
    }
}
