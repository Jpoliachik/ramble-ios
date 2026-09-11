//
//  WatchRambleIntents.swift
//  watch Watch App
//

import AppIntents

/// These intents ship with the watch app, so they record on the watch itself
/// instead of handing off to the iPhone. Assigning one to the Action Button
/// (Settings > Action Button > Shortcut) makes it a one-press recorder.
///
/// `openAppWhenRun` is required: watchOS only gives the microphone to a
/// foreground app, so the intent brings Ramble forward before recording.

struct WatchStartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Ramble on Apple Watch"
    static var description = IntentDescription(
        "Start recording a voice journal entry on Apple Watch",
        categoryName: "Recording"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await WatchRecordingManager.shared.startRecording().dialog)
    }
}

struct WatchStopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop my Ramble on Apple Watch"
    static var description = IntentDescription(
        "Stop the current Apple Watch recording and save it",
        categoryName: "Recording"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchRecordingManager.shared.stopRecordingAndTransfer() else {
            return .result(dialog: "No recording in progress.")
        }
        return .result(dialog: "Recording saved.")
    }
}

/// One press to start, one press to stop — the intent to put on the Action Button.
struct WatchToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble on Apple Watch"
    static var description = IntentDescription(
        "Start or stop a voice journal recording on Apple Watch",
        categoryName: "Recording"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = WatchRecordingManager.shared

        if manager.isRecording {
            manager.stopRecordingAndTransfer()
            return .result(dialog: "Recording saved.")
        }

        return .result(dialog: await manager.startRecording().dialog)
    }
}

extension WatchRecordingStartResult {
    var dialog: IntentDialog {
        switch self {
        case .started:
            return "Recording started."
        case .alreadyRecording:
            return "Already recording."
        case .microphoneDenied:
            return "Ramble needs microphone access. Turn it on in Settings > Privacy > Microphone."
        case .failed:
            return "Couldn't start recording. Try again in a moment."
        }
    }
}
