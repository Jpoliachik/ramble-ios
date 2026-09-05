//
//  RambleActivityAttributes.swift
//  Ramble / RambleWidgets
//
//  Compiled into both the app and the widget extension: the app starts and
//  updates the activity, the extension renders it.
//

import ActivityKit
import AppIntents
import Foundation

struct RambleActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Recording start, so the Live Activity can run its own timer instead of
        /// the app pushing an update every second.
        var startedAt: Date
    }
}

// MARK: - Live Activity buttons

/// `LiveActivityIntent` performs in the *app* process, which is what lets these
/// buttons touch the recorder. The type still has to compile into the widget
/// extension so the button can reference it, hence the `WIDGET_EXT` guard: the
/// extension has no `RecordingManager`, and never runs this body.
struct StopRambleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Ramble"
    static var description = IntentDescription("Stop recording and keep the audio")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        // The activity also runs for a watch recording, where the phone has nothing
        // to stop and has to ask the watch instead.
        if RecordingManager.shared.isRecording {
            RecordingManager.shared.stopRecording()
        } else {
            PhoneConnectivityService.shared.requestWatchStopRecording()
        }
        #endif
        return .result()
    }
}

struct CancelRambleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Discard Ramble"
    static var description = IntentDescription("Stop recording and discard the audio")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        if RecordingManager.shared.isRecording {
            RecordingManager.shared.cancelRecording()
        } else {
            // No discard channel to the watch, so the best available action is
            // asking it to stop; the recording is then kept, not thrown away.
            PhoneConnectivityService.shared.requestWatchStopRecording()
        }
        #endif
        return .result()
    }
}
