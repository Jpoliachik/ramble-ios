//
//  Constants.swift
//  Ramble
//

import Foundation

enum Constants {
    enum AudioSettings {
        static let sampleRate: Double = 16000
        static let numberOfChannels: Int = 1
        /// 32 kbps keeps a 60-minute note under the relay's 20 MB limit
        /// (specs/transcription.md "60-minute cap").
        static let bitRate: Int = 32000
    }

    enum Recording {
        /// One warning haptic and a countdown from here.
        static let warningDuration: TimeInterval = 55 * 60
        /// Recordings stop here, like a tapped stop.
        static let maxDuration: TimeInterval = 60 * 60
    }

    enum Relay {
        /// Ramble's relay. Identical API to https://api.ramble.watch, which
        /// isn't routed yet.
        static let hostedBaseURL = URL(string: "https://ramble-transcription-proxy.jpoliachik.workers.dev")!

        /// UserDefaults key a staging build sets to point at another relay.
        /// Only the Debug sheet (debug builds) edits it.
        static let baseURLOverrideKey = "relayBaseURLOverride"

        /// Debug builds only: X-Dev-Bypass for a local `wrangler dev` relay.
        static let devBypassKey = "devOverrideKey"

        static let supportEmail = "support@ramble.watch"

        static var baseURL: URL {
            if let override = UserDefaults.standard.string(forKey: baseURLOverrideKey),
               !override.isEmpty,
               let url = URL(string: override) {
                return url
            }
            return hostedBaseURL
        }
    }
}
