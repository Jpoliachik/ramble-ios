//
//  WatchRambleIntents.swift
//  watch Watch App
//

import AppIntents

struct WatchStartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Ramble"
    static var description: IntentDescription = "Start recording a voice journal entry"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WatchRecordingManager.shared.startRecording()
        return .result(dialog: "Recording started.")
    }
}

struct WatchStopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop my Ramble"
    static var description: IntentDescription = "Stop the current recording and save it"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchRecordingManager.shared.isRecording else {
            return .result(dialog: "No recording in progress.")
        }
        WatchRecordingManager.shared.stopRecordingAndTransfer()
        return .result(dialog: "Recording saved.")
    }
}

struct WatchToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a voice journal recording"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = WatchRecordingManager.shared
        if manager.isRecording {
            manager.stopRecordingAndTransfer()
            return .result(dialog: "Recording saved.")
        } else {
            manager.startRecording()
            return .result(dialog: "Recording started.")
        }
    }
}
