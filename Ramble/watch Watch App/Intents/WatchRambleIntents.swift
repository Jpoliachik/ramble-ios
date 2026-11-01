//
//  WatchRambleIntents.swift
//  watch Watch App
//

import AppIntents

struct WatchStartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Ramble"
    static var description: IntentDescription = "Start recording on your watch"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchRecordingManager.shared.startRecording() else {
            return .result(dialog: "Couldn't start recording.")
        }
        return .result(dialog: "Recording started.")
    }
}

struct WatchStopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop my Ramble"
    static var description: IntentDescription = "Stop the current recording and send it to your iPhone"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchRecordingManager.shared.isRecording else {
            return .result(dialog: "No recording in progress.")
        }
        WatchRecordingManager.shared.stopRecordingAndTransfer()
        return .result(dialog: "Saved on watch.")
    }
}

struct WatchToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a recording"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = WatchRecordingManager.shared
        if manager.isRecording {
            manager.stopRecordingAndTransfer()
            return .result(dialog: "Saved on watch.")
        } else {
            guard manager.startRecording() else {
                return .result(dialog: "Couldn't start recording.")
            }
            return .result(dialog: "Recording started.")
        }
    }
}
