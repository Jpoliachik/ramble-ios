//
//  WatchRambleShortcuts.swift
//  watch Watch App
//

import AppIntents

/// One shortcut: the Action button and Siri start or stop with the same action.
struct WatchRambleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchToggleRecordingIntent(),
            phrases: [
                "\(.applicationName)",
                "Toggle \(.applicationName)",
                "Start a \(.applicationName)",
                "Start recording with \(.applicationName)",
                "Stop my \(.applicationName)",
                "Stop recording with \(.applicationName)"
            ],
            shortTitle: "Ramble",
            systemImageName: "mic.fill"
        )
    }
}
