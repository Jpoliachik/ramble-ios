//
//  WatchRambleShortcuts.swift
//  watch Watch App
//

import AppIntents

struct WatchRambleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchStartRecordingIntent(),
            phrases: [
                "Start a \(.applicationName)",
                "Start recording with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: WatchStopRecordingIntent(),
            phrases: [
                "Stop my \(.applicationName)",
                "Stop recording with \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: WatchToggleRecordingIntent(),
            phrases: [
                "\(.applicationName)",
                "Toggle \(.applicationName)"
            ],
            shortTitle: "Ramble",
            systemImageName: "mic.badge.plus"
        )
    }
}
