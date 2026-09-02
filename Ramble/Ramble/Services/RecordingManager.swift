//
//  RecordingManager.swift
//  Ramble
//

import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var inputSourceName: String?
    @Published private(set) var audioLevel: Float = 0

    private let audioRecorder = AudioRecorderService()
    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared
    private let connectivity = PhoneConnectivityService.shared
    private var currentRecording: Recording?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeRecorder()
    }

    private func observeRecorder() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
        audioRecorder.$currentDuration.assign(to: &$currentDuration)
        audioRecorder.$inputSourceName.assign(to: &$inputSourceName)
        audioRecorder.$audioLevel.assign(to: &$audioLevel)
    }

    func startRecording() async {
        // Guarded here, not just in the UI, so Siri/Shortcuts/widget entry points
        // can't start a recording the selected model can't transcribe yet.
        if let blocked = LocalWhisperTranscriptionService.shared.recordingBlockedReason {
            print("Recording blocked: \(blocked)")
            return
        }

        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .undetermined {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                print("Microphone permission denied")
                return
            }
        } else if session.recordPermission == .denied {
            print("Microphone permission denied")
            return
        }

        let recording = Recording()
        currentRecording = recording

        do {
            try audioRecorder.startRecording(to: recording.audioFileURL)
            connectivity.sendRecordingStarted()
            LiveActivityService.shared.start()
        } catch {
            print("Failed to start recording: \(error)")
            currentRecording = nil
        }
    }

    func stopRecording() {
        let duration = audioRecorder.stopRecording()
        connectivity.sendRecordingStopped()
        LiveActivityService.shared.stop()

        guard var recording = currentRecording else { return }
        recording.duration = duration
        recording.activityLog.append(ActivityEntry("Recording captured on iPhone"))
        if let note = LiveActivityService.shared.consumeLastNote() {
            recording.activityLog.append(ActivityEntry(note))
        }

        // A tap that starts and stops in the same moment leaves a file with no
        // speech in it. Transcribing it can only fail, so say so up front instead
        // of sending it round the queue.
        if duration < Constants.Recording.minimumTranscribableDuration {
            recording.status = .failed
            recording.lastError = "Recording too short"
            recording.activityLog.append(ActivityEntry("Too short to transcribe — not queued"))
            storageService.addRecording(recording)
            currentRecording = nil
            return
        }

        storageService.addRecording(recording)

        // Don't transcribe until the file on disk is actually complete.
        // `AVAudioRecorder.stop()` closes the file, but finalizing the m4a container
        // can lag a moment, and a transcription that starts too early reads almost
        // no audio and fails with "no speech detected".
        let recordingId = recording.id
        let audioURL = recording.audioFileURL
        // Stopping from a Live Activity, a widget or a Shortcut happens while the
        // app is in the background, where it holds no background assertion and is
        // suspended as soon as the intent returns. Without this the transcript only
        // appears when the app is next opened, the same failure the watch handoff
        // had.
        let needsBackgroundTime = UIApplication.shared.applicationState != .active

        Task { [transcriptionQueue] in
            await Self.waitForFinalizedAudio(at: audioURL, expecting: duration)
            transcriptionQueue.enqueue(recordingId: recordingId)

            if needsBackgroundTime {
                BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
                BackgroundTaskService.shared.scheduleSyncTask()
            }
        }

        currentRecording = nil
    }

    /// Poll until the file reports roughly the duration that was recorded, or give
    /// up. Giving up still enqueues: a genuinely broken file should fail with a real
    /// error rather than never being tried.
    private static func waitForFinalizedAudio(
        at url: URL,
        expecting duration: TimeInterval,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let file = try? AVAudioFile(forReading: url) {
                let onDisk = Double(file.length) / file.fileFormat.sampleRate
                if onDisk >= duration * 0.8 { return }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func cancelRecording() {
        _ = audioRecorder.stopRecording()
        connectivity.sendRecordingStopped()
        LiveActivityService.shared.stop()

        // Delete the audio file without saving the recording
        if let recording = currentRecording {
            try? FileManager.default.removeItem(at: recording.audioFileURL)
        }
        currentRecording = nil
    }
}
