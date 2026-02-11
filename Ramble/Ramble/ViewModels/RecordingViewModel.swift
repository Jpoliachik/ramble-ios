//
//  RecordingViewModel.swift
//  Ramble

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

    private let recordingManager = RecordingManager.shared
    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared
    private let connectivity = PhoneConnectivityService.shared
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var watchRecordingDuration: TimeInterval {
        guard let startTime = watchRecordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    init() {
        loadRecordings()
        observeRecordingManager()
        observeConnectivity()
        startRefreshTimer()
        transcriptionQueue.resumePendingJobs()
    }

    private func observeRecordingManager() {
        recordingManager.$isRecording.assign(to: &$isRecording)
        recordingManager.$currentDuration.assign(to: &$currentDuration)
        recordingManager.$inputSourceName.assign(to: &$inputSourceName)
        recordingManager.$audioLevel.assign(to: &$audioLevel)
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
        recordingManager.stopRecording()
        loadRecordings()
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
            recordingManager.stopRecording()
            loadRecordings()
            showSavedConfirmation = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showSavedConfirmation = false
        } else {
            HapticService.recordStart()
            await recordingManager.startRecording()
        }
    }

    func stopWatchRecording() {
        connectivity.requestWatchStopRecording()
    }

    func deleteRecording(_ recording: Recording) {
        storageService.deleteRecording(recording)
        loadRecordings()
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
