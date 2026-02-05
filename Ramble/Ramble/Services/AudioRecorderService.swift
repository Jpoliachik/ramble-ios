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
    @Published private(set) var inputSourceName: String?
    @Published private(set) var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentRecordingURL: URL?

    private var isSessionActive = false

    override init() {
        super.init()
        prepareAudioSession()
    }

    /// Pre-warm the audio session so record starts instantly
    func prepareAudioSession() {
        guard !isSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // allowBluetooth enables AirPods/Bluetooth HFP mic input
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)
            isSessionActive = true
        } catch {
            print("Failed to prepare audio session: \(error)")
        }
    }

    func startRecording(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()

        // Ensure session is active (should already be from init)
        if !isSessionActive {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)
            isSessionActive = true
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: Constants.AudioSettings.sampleRate,
            AVNumberOfChannelsKey: Constants.AudioSettings.numberOfChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self
        audioRecorder?.record()

        currentRecordingURL = url
        recordingStartTime = Date()
        isRecording = true
        currentDuration = 0
        inputSourceName = Self.friendlyInputName(session.currentRoute.inputs.first)

        startTimer()
    }

    /// Convert port description to user-friendly name
    private static func friendlyInputName(_ port: AVAudioSessionPortDescription?) -> String? {
        guard let port = port else { return nil }
        switch port.portType {
        case .builtInMic:
            return "iPhone"
        case .bluetoothHFP:
            // Use device name (e.g., "AirPods Pro")
            return port.portName
        case .headsetMic:
            return "Headset"
        default:
            return port.portName
        }
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
        inputSourceName = nil
        audioLevel = 0

        return duration
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
        // Map -50dB..0dB to 0..1, clamp
        max(0, min(1, (dB + 50) / 50))
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
