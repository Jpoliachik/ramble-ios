//
//  WatchRecordingManager.swift
//  watch Watch App
//
//  Starts and stops recordings, and hands each saved note on: to the store,
//  to the relay upload (started at the stop, while the app is in front),
//  and to the iPhone (details now, audio in the background).
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class WatchRecordingManager: ObservableObject {
    static let shared = WatchRecordingManager()

    /// From here the timer counts down and one haptic plays.
    static let warnAt: TimeInterval = 55 * 60
    static let maxDuration: TimeInterval = WatchAudioRecorderService.maxDuration

    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0
    /// Bumped every time a recording is saved, however it stopped: the
    /// button, double tap, Siri, the 60-minute cap, or a call taking the
    /// mic. Home shows the same check for all of them.
    @Published private(set) var stopCount = 0

    private let audioRecorder = WatchAudioRecorderService()
    private var warnedThisRecording = false
    private var isStarting = false

    private init() {
        observeRecorder()
        audioRecorder.onEndedBySystem = { [weak self] in
            // A call, Siri or the cap took the mic. Keep what was said so far.
            self?.stopRecording()
        }
    }

    /// Get the next recording ready before the tap. Call when the app
    /// appears, returns to the foreground, or finishes a recording.
    func prewarm() {
        audioRecorder.prewarm()
    }

    /// Deletes header-only files from prepared recorders that never ran.
    func removeUnusedPreparedFiles() {
        audioRecorder.removeUnusedPreparedFiles(keeping: WatchNoteStore.shared.audioFileNames)
    }

    private func observeRecorder() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
        audioRecorder.$audioLevel.assign(to: &$audioLevel)
        audioRecorder.$currentDuration
            .sink { [weak self] duration in
                self?.currentDuration = duration
                self?.checkCap(duration)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    /// One notification haptic at 55:00, and a normal stop at 60:00.
    private func checkCap(_ duration: TimeInterval) {
        guard isRecording else { return }
        if duration >= Self.maxDuration {
            // Off this publisher's callback, since stopping resets it
            Task { @MainActor in self.stopRecording() }
        } else if duration >= Self.warnAt, !warnedThisRecording {
            warnedThisRecording = true
            WatchHapticService.capWarning()
        }
    }

    /// True when the person has turned the microphone off for Ramble.
    var isMicrophoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Starts at once, without waiting on the iPhone, the network or setup.
    /// Returns false if recording could not start. Asks for microphone
    /// access first if it hasn't been asked yet. Plays the start haptic.
    @discardableResult
    func startRecording() async -> Bool {
        guard !isRecording, !isStarting else { return isRecording }
        isStarting = true
        defer { isStarting = false }

        guard await Self.hasMicrophoneAccess() else { return false }

        do {
            _ = try audioRecorder.startRecording()
            warnedThisRecording = false
            WatchHapticService.recordStart()
            return true
        } catch {
            print("Failed to start recording: \(error)")
            return false
        }
    }

    private static func hasMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return true
        }
    }

    /// Every stop looks and feels the same: saved at once, success haptic,
    /// and the check on Home.
    func stopRecording() {
        guard let result = audioRecorder.stopRecording() else { return }
        WatchHapticService.recordStop()

        let audioFileName = result.url.lastPathComponent
        let id = UUID(uuidString: (audioFileName as NSString).deletingPathExtension) ?? UUID()
        let duration = min(result.duration, Self.maxDuration)
        let note = WatchNoteRecord(
            id: id,
            recordedAt: Date().addingTimeInterval(-result.duration),
            duration: duration,
            audioFileName: audioFileName
        )
        WatchNoteStore.shared.add(note)
        stopCount += 1

        // The upload starts now, while the app is still in front.
        WatchRelayService.shared.noteSaved(note)
        // The phone lists it before its transcript, and gets the audio later.
        WatchConnectivityService.shared.sendNoteDetails(note)
        WatchConnectivityService.shared.sendAudio(note)

        // Ready for the next one straight away
        Task { @MainActor in
            self.prewarm()
        }
    }
}
