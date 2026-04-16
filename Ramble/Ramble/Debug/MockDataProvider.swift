//
//  MockDataProvider.swift
//  Ramble
//
//  Mock data for App Store screenshots. Not shipped in release builds.
//

#if DEBUG

import Foundation

enum MockDataProvider {
    /// Flip this to `true`, run the app, take screenshots.
    static var enabled = false

    static func mockRecordings() -> [Recording] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return [
            // --- Today ---
            Recording(
                createdAt: today.addingTimeInterval(9 * 3600 + 1200), // 9:20 AM
                duration: 47,
                status: .completed,
                transcription: "Follow-up note from the call with Amber at Vantage. They're interested in the enterprise plan but want to see a SOC 2 report before moving forward. Send it over today, schedule a technical deep-dive for next week, and loop in Dave from security. Mark the deal as stage two in the CRM.",
                webhookStatus: .delivered,
                activityLog: [
                    ActivityEntry("Transcribed via Whisper v3 Turbo", httpStatus: 200),
                    ActivityEntry("Sent to API", httpStatus: 200),
                ]
            ),
            Recording(
                createdAt: today.addingTimeInterval(8 * 3600 + 600), // 8:10 AM
                duration: 124,
                status: .completed,
                transcription: "Morning walk notes. The park was quiet today, just a few runners. I've been thinking about the API design for webhooks. We should support both JSON and form-encoded payloads. Most automation tools like Zapier and Make expect JSON, but some older systems still use form encoding. Let's default to JSON and add a toggle later if anyone asks. Also need to remember to pick up coffee beans on the way home.",
                webhookStatus: .delivered,
                activityLog: [
                    ActivityEntry("Transcribed via Whisper v3 Turbo", httpStatus: 200),
                    ActivityEntry("Sent to API", httpStatus: 200),
                ]
            ),

            // --- Yesterday ---
            Recording(
                createdAt: yesterday.addingTimeInterval(20 * 3600 + 1800), // 8:30 PM
                duration: 35,
                status: .completed,
                transcription: "Reminder to self: update the privacy policy before submitting to App Store review. Apple requires a valid URL and the current draft still references placeholder company names.",
                webhookStatus: .delivered,
                activityLog: [
                    ActivityEntry("Transcribed via Apple Speech", httpStatus: nil),
                    ActivityEntry("Sent to API", httpStatus: 200),
                ]
            ),
            Recording(
                createdAt: yesterday.addingTimeInterval(14 * 3600 + 900), // 2:15 PM
                duration: 203,
                status: .completed,
                transcription: "Ramble is private by design. No accounts. No user data on our servers. Your audio and transcripts stay on your device unless you choose to send them somewhere. The transcription proxy is stateless — audio comes in, text goes out, nothing is logged. The entire codebase is open source. Don't take our word for it. Read the code.",
                webhookStatus: .delivered,
                activityLog: [
                    ActivityEntry("Transcribed via Nova-3", httpStatus: 200),
                    ActivityEntry("Sent to API", httpStatus: 200),
                ]
            ),
            Recording(
                createdAt: yesterday.addingTimeInterval(10 * 3600 + 300), // 10:05 AM
                duration: 18,
                status: .completed,
                transcription: "Quick thought: we should add haptic feedback when the recording starts and stops. A subtle tap, nothing aggressive. It confirms the action without needing to look at the screen — especially useful on Apple Watch.",
                webhookStatus: .delivered,
                activityLog: [
                    ActivityEntry("Transcribed via Whisper v3 Turbo", httpStatus: 200),
                    ActivityEntry("Sent to API", httpStatus: 200),
                ]
            ),
        ]
    }
}

#endif
