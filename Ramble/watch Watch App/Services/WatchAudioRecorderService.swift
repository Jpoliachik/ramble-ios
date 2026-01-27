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
    @Published private(set) var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private(set) var currentRecordingURL: URL?

    private var isSessionActive = false

    override init() {
        super.init()
        prepareAudioSession()
    }

    func prepareAudioSession() {
        guard !isSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            isSessionActive = true
        } catch {
            print("Failed to prepare watch audio session: \(error)")
        }
    }

    func startRecording() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        if !isSessionActive {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            isSessionActive = true
        }

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
        audioRecorder?.isMeteringEnabled = true
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
        audioLevel = 0
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
                self.audioRecorder?.updateMeters()
                let dB = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                self.audioLevel = Self.normalizeAudioLevel(dB)
            }
        }
    }

    private static func normalizeAudioLevel(_ dB: Float) -> Float {
        max(0, min(1, (dB + 50) / 50))
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
