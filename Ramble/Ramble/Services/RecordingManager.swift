//
//  RecordingManager.swift
//  Ramble
//

import AVFoundation
import Combine
import Foundation

enum RecordingStartError: Equatable {
    case microphoneDenied
    case failed(String)

    var message: String {
        switch self {
        case .microphoneDenied:
            return "Ramble doesn't have microphone access. Turn it on in Settings to record."
        case .failed(let reason):
            return reason
        }
    }
}

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var inputSourceName: String?
    @Published private(set) var audioLevel: Float = 0
    /// Why the last start attempt failed, so the UI can say so instead of
    /// silently doing nothing. Cleared on the next attempt.
    @Published private(set) var startError: RecordingStartError?

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
        startError = nil

        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .undetermined {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                startError = .microphoneDenied
                return
            }
        } else if session.recordPermission == .denied {
            startError = .microphoneDenied
            return
        }

        // Ask before recording so the prompt doesn't land mid-recording
        await LegacySpeechTranscriptionService.requestAuthorizationIfNeeded()

        let recording = Recording()
        currentRecording = recording

        do {
            try audioRecorder.startRecording(to: recording.audioFileURL)
            connectivity.sendRecordingStarted()
        } catch {
            print("Failed to start recording: \(error)")
            currentRecording = nil
            startError = .failed(error.localizedDescription)
        }
    }

    func clearStartError() {
        startError = nil
    }

    func stopRecording() {
        let duration = audioRecorder.stopRecording()
        connectivity.sendRecordingStopped()

        guard var recording = currentRecording else { return }
        recording.duration = duration

        storageService.addRecording(recording)

        transcriptionQueue.enqueue(recordingId: recording.id)

        currentRecording = nil
    }

    func cancelRecording() {
        _ = audioRecorder.stopRecording()
        connectivity.sendRecordingStopped()

        // Delete the audio file without saving the recording
        if let recording = currentRecording {
            try? FileManager.default.removeItem(at: recording.audioFileURL)
        }
        currentRecording = nil
    }
}
