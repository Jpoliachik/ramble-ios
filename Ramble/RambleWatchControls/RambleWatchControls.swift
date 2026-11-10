//
//  RambleWatchControls.swift
//  RambleWatchControls
//
//  The Ramble control for the watch (watchOS 26+): Action button on
//  Apple Watch Ultra, Control Center and the Smart Stack.
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct RambleWatchControlsBundle: WidgetBundle {
    var body: some Widget {
        RambleRecordControl()
    }
}

struct RambleRecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.goodloop.Ramble.watchkitapp.record") {
            ControlWidgetButton(action: WatchToggleRecordingIntent()) {
                Label("Ramble", systemImage: "mic.fill")
            }
        }
        .displayName("Ramble")
        .description("Start or stop a recording.")
    }
}

/// The watch app's own WatchToggleRecordingIntent, named here so the control
/// can point at it. It must keep the same type name and title as the app's.
/// It asks to run in the foreground, so the system opens Ramble and runs the
/// app's perform(), which records. This one never records.
struct WatchToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a recording"
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
