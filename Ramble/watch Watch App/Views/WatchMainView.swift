//
//  WatchMainView.swift
//  watch Watch App
//

import Combine
import SwiftUI

struct WatchMainView: View {
    @StateObject private var recordingManager = WatchRecordingManager.shared
    @StateObject private var connectivity = WatchConnectivityService.shared
    @StateObject private var syncQueue = WatchSyncQueue.shared

    @State private var showSaved = false
    @State private var phoneRecordingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    @State private var stopRequestCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Status indicator
            statusView

            // Timer
            timerView

            Spacer()

            // Record button
            WatchRecordButtonView(
                isRecording: recordingManager.isRecording || connectivity.phoneIsRecording,
                audioLevel: recordingManager.audioLevel
            ) {
                Task {
                    await toggleRecording()
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            subscribeToStopRequests()
            connectivity.queryPhoneState()

            // Retry any pending transfers from previous sessions
            syncQueue.pruneOrphanedJobs()
            connectivity.retryPendingTransfers()
        }
        .onDisappear {
            stopRequestCancellable?.cancel()
        }
        .onChange(of: connectivity.phoneIsRecording) { _, isRecording in
            if isRecording {
                startPhoneDurationTimer()
            } else {
                stopPhoneDurationTimer()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if showSaved {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.caption)
            }
            .transition(.opacity)
        } else if connectivity.isTransferring {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.caption)
            }
        } else if syncQueue.pendingCount > 0 && !connectivity.isTransferring {
            HStack {
                Image(systemName: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundStyle(.orange)
                Text("\(syncQueue.pendingCount) unsent")
                    .font(.caption)
            }
            .onTapGesture {
                connectivity.retryPendingTransfers()
            }
        } else if connectivity.phoneIsRecording {
            HStack {
                Image(systemName: "iphone")
                    .foregroundStyle(.red)
                Text("Recording")
                    .font(.caption)
            }
        } else {
            Text("Ramble")
                .font(.system(.headline, design: .serif))
                .italic()
        }
    }

    @ViewBuilder
    private var timerView: some View {
        if recordingManager.isRecording {
            Text(formatDuration(recordingManager.currentDuration))
                .font(.system(size: 32, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(.red)
                .contentTransition(.numericText())
        } else if connectivity.phoneIsRecording {
            Text(formatDuration(phoneRecordingDuration))
                .font(.system(size: 32, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(.red)
                .contentTransition(.numericText())
        } else {
            Text(formatDuration(0))
                .font(.system(size: 32, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func subscribeToStopRequests() {
        stopRequestCancellable = connectivity.stopRequestReceived
            .receive(on: DispatchQueue.main)
            .sink {
                Task {
                    await stopFromPhoneRequest()
                }
            }
    }

    private func stopFromPhoneRequest() async {
        guard recordingManager.isRecording else { return }
        WatchHapticService.recordStop()
        recordingManager.stopRecordingAndTransfer()
        await showSavedConfirmation()
    }

    private func startPhoneDurationTimer() {
        phoneRecordingDuration = 0
        if let startTime = connectivity.phoneRecordingStartTime {
            phoneRecordingDuration = Date().timeIntervalSince(startTime)
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = connectivity.phoneRecordingStartTime {
                phoneRecordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopPhoneDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        phoneRecordingDuration = 0
    }

    private func toggleRecording() async {
        if connectivity.phoneIsRecording {
            WatchHapticService.recordStop()
            connectivity.requestPhoneStopRecording()
            return
        }

        if recordingManager.isRecording {
            WatchHapticService.recordStop()
            recordingManager.stopRecordingAndTransfer()
            await showSavedConfirmation()
        } else {
            WatchHapticService.recordStart()
            recordingManager.startRecording()
        }
    }

    private func showSavedConfirmation() async {
        showSaved = true
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        showSaved = false
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    WatchMainView()
}
