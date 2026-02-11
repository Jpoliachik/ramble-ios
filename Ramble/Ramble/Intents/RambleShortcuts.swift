//
//  RambleShortcuts.swift
//  Ramble
//

import AppIntents

struct RambleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start a \(.applicationName)",
                "Start recording with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop my \(.applicationName)",
                "Stop recording with \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "\(.applicationName)",
                "Toggle \(.applicationName)"
            ],
            shortTitle: "Ramble",
            systemImageName: "mic.badge.plus"
        )
    }
}
