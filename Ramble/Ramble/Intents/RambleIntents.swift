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
    func perform() async throws -> some IntentResult {
        await RecordingManager.shared.startRecording()
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop my Ramble"
    static var description: IntentDescription = "Stop the current recording and save it"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if RecordingManager.shared.isRecording {
            RecordingManager.shared.stopRecording()
        }
        return .result()
    }
}

struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a voice journal recording"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = RecordingManager.shared
        if manager.isRecording {
            manager.stopRecording()
        } else {
            await manager.startRecording()
        }
        return .result()
    }
}
