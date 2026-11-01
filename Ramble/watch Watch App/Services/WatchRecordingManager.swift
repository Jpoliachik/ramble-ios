//
//  WatchRecordingManager.swift
//  watch Watch App
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class WatchRecordingManager: ObservableObject {
    static let shared = WatchRecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0

    private let audioRecorder = WatchAudioRecorderService()
    private let connectivity = WatchConnectivityService.shared
    private let syncQueue = WatchSyncQueue.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeRecorder()
    }

    private func observeRecorder() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
        audioRecorder.$currentDuration.assign(to: &$currentDuration)
        audioRecorder.$audioLevel.assign(to: &$audioLevel)
    }

    private var isStarting = false

    /// True when the user has turned the microphone off for Ramble.
    var isMicrophoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Returns false if recording could not start (e.g. no microphone access).
    /// Asks for microphone access first if it hasn't been asked yet.
    @discardableResult
    func startRecording() async -> Bool {
        guard !isRecording, !isStarting else { return isRecording }
        isStarting = true
        defer { isStarting = false }

        guard await Self.hasMicrophoneAccess() else { return false }

        do {
            _ = try audioRecorder.startRecording()
            connectivity.sendRecordingStarted()
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

    func stopRecordingAndTransfer() {
        guard let result = audioRecorder.stopRecording() else { return }
        connectivity.sendRecordingStopped()

        // Add to persistent queue FIRST, then attempt transfer
        let audioFileName = result.url.lastPathComponent
        // createdAt is when the recording started, matching the phone's own recordings
        let job = syncQueue.addJob(
            audioFileName: audioFileName,
            createdAt: Date().addingTimeInterval(-result.duration),
            duration: result.duration
        )

        // Track in recording history for the list UI
        WatchRecordingHistory.shared.addEntry(
            id: job.id,
            createdAt: job.createdAt,
            duration: job.duration
        )

        connectivity.transferJob(job)
    }
}
