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

/// The watch's only intent: start or stop, like the button. Silent both ways
/// so the start path never speaks. The haptic tells you which way it went.
/// Opens Ramble first: a recording started in the background is cut off.
struct WatchToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ramble"
    static var description: IntentDescription = "Start or stop a recording"
    static var openAppWhenRun = true
    @available(watchOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

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
