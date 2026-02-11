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
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeRecorder()
    }

    private func observeRecorder() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
        audioRecorder.$currentDuration.assign(to: &$currentDuration)
        audioRecorder.$audioLevel.assign(to: &$audioLevel)
    }

    func startRecording() {
        do {
            _ = try audioRecorder.startRecording()
            connectivity.sendRecordingStarted()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecordingAndTransfer() {
        guard let result = audioRecorder.stopRecording() else { return }
        connectivity.sendRecordingStopped()
        connectivity.transferRecording(url: result.url, duration: result.duration)
    }
}
