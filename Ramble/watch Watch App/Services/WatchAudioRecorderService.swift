//
//  WatchAudioRecorderService.swift
//  watch Watch App
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class WatchAudioRecorderService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private(set) var currentRecordingURL: URL?

    override init() {
        super.init()
    }

    func startRecording() async throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let recordingId = UUID().uuidString
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let audioURL = documentsPath.appendingPathComponent("\(recordingId).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()

        currentRecordingURL = audioURL
        recordingStartTime = Date()
        isRecording = true
        currentDuration = 0

        startTimer()

        return audioURL
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate()
        timer = nil

        let duration = currentDuration
        let url = currentRecordingURL

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentDuration = 0
        recordingStartTime = nil
        currentRecordingURL = nil

        guard let recordingURL = url else { return nil }
        return (url: recordingURL, duration: duration)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    func deleteLocalFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

extension WatchAudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        if !flag {
            print("Watch recording finished unsuccessfully")
        }
    }
}
