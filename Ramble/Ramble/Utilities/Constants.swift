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

        #if DEBUG && targetEnvironment(simulator)
        /// Simulators can't use App Attest, so debug simulator builds talk to
        /// a local relay (`cd proxy`, `npm run dev`) that takes the bypass key
        /// from proxy/.dev.vars. Production never accepts it.
        static let localBaseURL = URL(string: "http://localhost:8787")!
        static let localDevBypassKey = "ramble-local-dev-bypass-key"
        #endif

        static var baseURL: URL {
            if let override = UserDefaults.standard.string(forKey: baseURLOverrideKey),
               !override.isEmpty,
               let url = URL(string: override) {
                return url
            }
            #if DEBUG && targetEnvironment(simulator)
            return localBaseURL
            #else
            return hostedBaseURL
            #endif
        }

        /// X-Dev-Bypass value, or "" to use App Attest. Always "" in release builds.
        static var devBypass: String {
            #if DEBUG
            if let key = UserDefaults.standard.string(forKey: devBypassKey), !key.isEmpty { return key }
            #if targetEnvironment(simulator)
            return localDevBypassKey
            #else
            return ""
            #endif
            #else
            return ""
            #endif
        }
    }
}

/// The one privacy wording (specs/delivery.md "One privacy wording everywhere").
enum PrivacyCopy {
    static let relay = "Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone."
}
