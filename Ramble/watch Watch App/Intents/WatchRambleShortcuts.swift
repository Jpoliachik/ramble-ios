//
//  WatchRambleShortcuts.swift
//  watch Watch App
//

import AppIntents

/// App Shortcuts published by the watch app itself. They show up in the
/// Shortcuts app on Apple Watch and in Settings > Action Button > Shortcut,
/// and they run on the watch instead of waking the iPhone.
///
/// The iPhone app publishes shortcuts with the same names, so the short titles
/// here say "on Watch" to make the watch-local ones easy to pick out of the
/// Action Button list. The toggle comes first: it's the one that turns the
/// Action Button into a press-to-start, press-to-stop recorder.
struct WatchRambleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchToggleRecordingIntent(),
            phrases: [
                "\(.applicationName)",
                "Toggle \(.applicationName)",
                "\(.applicationName) on my watch"
            ],
            shortTitle: "Ramble on Watch",
            systemImageName: "mic.badge.plus"
        )
        AppShortcut(
            intent: WatchStartRecordingIntent(),
            phrases: [
                "Start a \(.applicationName)",
                "Start recording with \(.applicationName)",
                "Start a \(.applicationName) on my watch"
            ],
            shortTitle: "Record on Watch",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: WatchStopRecordingIntent(),
            phrases: [
                "Stop my \(.applicationName)",
                "Stop recording with \(.applicationName)",
                "Stop my \(.applicationName) on my watch"
            ],
            shortTitle: "Stop on Watch",
            systemImageName: "stop.fill"
        )
    }
}
