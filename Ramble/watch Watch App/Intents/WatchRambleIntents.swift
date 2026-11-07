//
//  WatchRambleIntents.swift
//  watch Watch App
//

import AppIntents

/// Starting stays silent: a spoken reply would land in the recording.
/// A haptic confirms the start instead. Failures are spoken, since nothing is recording.
nonisolated enum WatchRecordingIntentError: Error, CustomLocalizedStringResourceConvertible {
    case microphoneDenied
    case couldNotStart

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .microphoneDenied:
            return "Allow microphone in Settings."
        case .couldNotStart:
            return "Couldn't start recording."
        }
    }
}

@MainActor
private func startRecordingFromIntent() async throws {
    let manager = WatchRecordingManager.shared
    guard await manager.startRecording() else {
        WatchHapticService.failure()
        throw manager.isMicrophoneDenied
            ? WatchRecordingIntentError.microphoneDenied
            : WatchRecordingIntentError.couldNotStart
    }
    // The start haptic comes from the manager, as for a tap
}

/// Same save, haptic and check as the button.
@MainActor
private func stopRecordingFromIntent() {
    WatchRecordingManager.shared.stopRecording()
}

struct WatchStartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Ramble"
    static var description: IntentDescription = "Start recording on your watch"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if !WatchRecordingManager.shared.isRecording {
            try await startRecordingFromIntent()
        }
        return .result()
    }
}

struct WatchStopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop my Ramble"
    static var description: IntentDescription = "Stop the current recording and send it"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchRecordingManager.shared.isRecording else {
            return .result(dialog: "No recording in progress.")
        }
        stopRecordingFromIntent()
        return .result(dialog: "Saved.")
    }
}

/// Silent both ways so the start path never speaks. The haptic tells you which way it went.
struct WatchToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a recording"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if WatchRecordingManager.shared.isRecording {
            stopRecordingFromIntent()
        } else {
            try await startRecordingFromIntent()
        }
        return .result()
    }
}
