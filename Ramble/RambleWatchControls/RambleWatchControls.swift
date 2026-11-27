//
//  RambleWatchControls.swift
//  RambleWatchControls
//
//  Ramble's watch face and Smart Stack pieces: the Ramble complication
//  (watchOS 10+), and the Ramble control (watchOS 26+) for the Action
//  button on Apple Watch Ultra, Control Center and the Smart Stack.
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct RambleWatchControlsBundle: WidgetBundle {
    var body: some Widget {
        RambleRecordComplication()
        if #available(watchOS 26.0, *) {
            RambleRecordControl()
        }
    }
}

@available(watchOS 26.0, *)
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
    @available(watchOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
