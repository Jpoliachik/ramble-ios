//
//  RambleIntents.swift
//  Ramble
//

import AppIntents

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Ramble"
    static var description: IntentDescription = "Start recording a voice journal entry"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = RecordingManager.shared
        await manager.startRecording()
        guard manager.isRecording else {
            return .result(dialog: "Couldn't start recording. \(manager.startError?.message ?? "")")
        }
        return .result(dialog: "Recording started.")
    }
}

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop my Ramble"
    static var description: IntentDescription = "Stop the current recording and save it"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard RecordingManager.shared.isRecording else {
            return .result(dialog: "No recording in progress.")
        }
        RecordingManager.shared.stopRecording()
        return .result(dialog: "Recording saved.")
    }
}

struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a voice journal recording"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = RecordingManager.shared
        if manager.isRecording {
            manager.stopRecording()
            return .result(dialog: "Recording saved.")
        } else {
            await manager.startRecording()
            guard manager.isRecording else {
                return .result(dialog: "Couldn't start recording. \(manager.startError?.message ?? "")")
            }
            return .result(dialog: "Recording started.")
        }
    }
}
