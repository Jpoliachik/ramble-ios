//
//  RecordingManager.swift
//  Ramble
//

import AVFoundation
import Combine
import Foundation

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
        } catch {
            print("Failed to start recording: \(error)")
            currentRecording = nil
        }
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
}
