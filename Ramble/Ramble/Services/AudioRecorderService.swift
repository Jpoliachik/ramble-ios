//
//  AudioRecorderService.swift
//  Ramble
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentRecordingURL: URL?

    override init() {
        super.init()
    }

    func startRecording(to url: URL) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: Constants.AudioSettings.sampleRate,
            AVNumberOfChannelsKey: Constants.AudioSettings.numberOfChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()

        currentRecordingURL = url
        recordingStartTime = Date()
        isRecording = true
        currentDuration = 0

        startTimer()
    }

    func stopRecording() -> TimeInterval {
        timer?.invalidate()
        timer = nil

        let duration = currentDuration
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentDuration = 0
        recordingStartTime = nil
        currentRecordingURL = nil

        return duration
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        if let error = error {
            print("Recording encode error: \(error.localizedDescription)")
        }
    }
}
