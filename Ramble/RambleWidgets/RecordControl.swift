//
//  RecordControl.swift
//  RambleWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Action Button / Lock Screen control.
///
/// A control button needs an `AppIntent`, not a URL, and an intent compiled into
/// this extension can't touch the app's recorder. So it returns an `OpenURLIntent`
/// and lets the app handle `ramble://record`, which is the same path the widget
/// and the watch complication take.
struct OpenRambleRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Ramble"
    static var description = IntentDescription("Open Ramble and start or stop recording")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "ramble://record")!))
    }
}

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.goodloop.Ramble.recordControl") {
            ControlWidgetButton(action: OpenRambleRecordIntent()) {
                Label("Ramble", systemImage: "mic.fill")
            }
        }
        .displayName("Ramble")
        .description("Start a Ramble.")
    }
}
