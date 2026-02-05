//
//  RecordingViewModel.swift
//  Ramble
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var inputSourceName: String?
    @Published private(set) var audioLevel: Float = 0
    @Published var showSavedConfirmation = false

    // Watch recording state (exposed from connectivity)
    @Published private(set) var watchIsRecording = false
    @Published private(set) var watchRecordingStartTime: Date?

    private let audioRecorder = AudioRecorderService()
    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared
    private let connectivity = PhoneConnectivityService.shared
    private var currentRecording: Recording?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var watchRecordingDuration: TimeInterval {
        guard let startTime = watchRecordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    init() {
        loadRecordings()
        observeRecorder()
        observeConnectivity()
        startRefreshTimer()
        transcriptionQueue.resumePendingJobs()
    }

    private func observeRecorder() {
        audioRecorder.$isRecording.assign(to: &$isRecording)
        audioRecorder.$currentDuration.assign(to: &$currentDuration)
        audioRecorder.$inputSourceName.assign(to: &$inputSourceName)
        audioRecorder.$audioLevel.assign(to: &$audioLevel)
    }

    private func observeConnectivity() {
        connectivity.$watchIsRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchIsRecording)

        connectivity.$watchRecordingStartTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchRecordingStartTime)

        connectivity.stopRequestReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    self?.stopRecordingFromWatch()
                }
            }
            .store(in: &cancellables)
    }

    private func stopRecordingFromWatch() {
        guard isRecording else { return }
        HapticService.recordStop()
        stopRecording()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadRecordings()
            }
        }
    }

    func loadRecordings() {
        recordings = storageService.loadRecordings()
    }

    func toggleRecording() async {
        if isRecording {
            HapticService.recordStop()
            stopRecording()
            showSavedConfirmation = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showSavedConfirmation = false
        } else {
            HapticService.recordStart()
            await startRecording()
        }
    }

    private func startRecording() async {
        // Check permission synchronously first; only prompt if undetermined
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

    private func stopRecording() {
        let duration = audioRecorder.stopRecording()
        connectivity.sendRecordingStopped()

        guard var recording = currentRecording else { return }
        recording.duration = duration

        storageService.addRecording(recording)
        loadRecordings()

        // Queue for transcription
        transcriptionQueue.enqueue(recordingId: recording.id)

        currentRecording = nil
    }

    func stopWatchRecording() {
        connectivity.requestWatchStopRecording()
    }

    func deleteRecording(_ recording: Recording) {
        storageService.deleteRecording(recording)
        loadRecordings()
    }

    func selectAudioInput(_ input: AudioInput) {
        audioRecorder.switchInput(to: input)
        // Update displayed input name
        inputSourceName = input.displayName
    }

    var recordingsByDay: [(date: Date, recordings: [Recording])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recordings) { recording in
            calendar.startOfDay(for: recording.createdAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, recordings: $0.value) }
    }
}
