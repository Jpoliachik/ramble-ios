//
//  WatchAudioRecorderService.swift
//  watch Watch App
//

import AVFoundation
import Combine
import Foundation

enum WatchRecordingError: LocalizedError {
    case microphonePermissionDenied
    case audioSessionUnavailable(Error)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Ramble needs microphone access. Turn it on in Settings > Privacy > Microphone."
        case .audioSessionUnavailable:
            return "The microphone is busy. Try again in a moment."
        }
    }
}

@MainActor
final class WatchAudioRecorderService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private(set) var currentRecordingURL: URL?

    /// Returns true once the microphone is usable, prompting the first time.
    func ensureMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startRecording() async throws -> URL {
        try await activateSession()

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

    /// Activating the session can fail for a beat when the app was cold-launched
    /// by an App Intent (Action Button, Siri) and isn't frontmost yet, so retry.
    private func activateSession() async throws {
        let session = AVAudioSession.sharedInstance()
        // allowBluetooth enables AirPods/Bluetooth HFP mic input
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try session.setActive(true)
                return
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
            }
        }

        throw WatchRecordingError.audioSessionUnavailable(
            lastError ?? NSError(domain: NSOSStatusErrorDomain, code: -1)
        )
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

        // Deactivate session so other audio can resume
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

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
