//
//  WatchRecordingManager.swift
//  watch Watch App
//

import AVFoundation
import Combine
import Foundation

enum WatchRecordingStartResult {
    case started
    case alreadyRecording
    case microphoneDenied
    case failed
}

@MainActor
final class WatchRecordingManager: ObservableObject {
    static let shared = WatchRecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0
    /// Briefly true after a recording is saved, so the UI can confirm regardless
    /// of whether the stop came from the button, the phone, or an App Intent.
    @Published private(set) var recentlySaved = false
    /// Set when a start attempt fails so the UI can explain why nothing happened.
    @Published private(set) var lastError: String?

    private let audioRecorder = WatchAudioRecorderService()
    private let connectivity = WatchConnectivityService.shared
    private let syncQueue = WatchSyncQueue.shared
    private var cancellables = Set<AnyCancellable>()
    private var savedConfirmationTask: Task<Void, Never>?
    private var errorClearTask: Task<Void, Never>?

    private init() {
        observeRecorder()
    }

    private func observeRecorder() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
        audioRecorder.$currentDuration.assign(to: &$currentDuration)
        audioRecorder.$audioLevel.assign(to: &$audioLevel)
    }

    /// Starts a recording on the watch. Safe to call from an App Intent on a
    /// cold launch — it prompts for the microphone and waits for the audio
    /// session instead of failing silently.
    @discardableResult
    func startRecording() async -> WatchRecordingStartResult {
        guard !isRecording else { return .alreadyRecording }

        clearError()

        guard await audioRecorder.ensureMicrophonePermission() else {
            report(WatchRecordingError.microphonePermissionDenied.errorDescription)
            return .microphoneDenied
        }

        do {
            _ = try await audioRecorder.startRecording()
            WatchHapticService.recordStart()
            connectivity.sendRecordingStarted()
            return .started
        } catch {
            report((error as? WatchRecordingError)?.errorDescription)
            print("Failed to start recording: \(error)")
            return .failed
        }
    }

    /// Stops the active recording, queues it for transfer, and confirms with a
    /// haptic. Returns false when nothing was recording.
    @discardableResult
    func stopRecordingAndTransfer() -> Bool {
        guard let result = audioRecorder.stopRecording() else { return false }

        WatchHapticService.recordStop()
        connectivity.sendRecordingStopped()

        // Add to persistent queue FIRST, then attempt transfer
        let audioFileName = result.url.lastPathComponent
        let job = syncQueue.addJob(
            audioFileName: audioFileName,
            createdAt: Date(),
            duration: result.duration
        )

        // Track in recording history for the list UI
        WatchRecordingHistory.shared.addEntry(
            id: job.id,
            createdAt: job.createdAt,
            duration: job.duration
        )

        connectivity.transferJob(job)
        flashSavedConfirmation()
        return true
    }

    /// Start if idle, stop if recording — what the record button and the
    /// Action Button shortcut both run.
    func toggleRecording() async {
        if isRecording {
            stopRecordingAndTransfer()
        } else {
            await startRecording()
        }
    }

    private func clearError() {
        errorClearTask?.cancel()
        errorClearTask = nil
        lastError = nil
    }

    /// Show the reason a start failed, then get out of the way.
    private func report(_ message: String?) {
        errorClearTask?.cancel()
        lastError = message ?? "Couldn't start recording."
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastError = nil
        }
    }

    private func flashSavedConfirmation() {
        savedConfirmationTask?.cancel()
        recentlySaved = true
        savedConfirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.recentlySaved = false
        }
    }
}
