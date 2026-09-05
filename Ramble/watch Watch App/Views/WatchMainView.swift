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
    @StateObject private var history = WatchRecordingHistory.shared

    @State private var showSaved = false
    @State private var phoneRecordingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    @State private var stopRequestCancellable: AnyCancellable?
    @State private var showCancelConfirmation = false

    private var isRecording: Bool {
        recordingManager.isRecording || connectivity.phoneIsRecording
    }

    private var currentDuration: TimeInterval {
        if recordingManager.isRecording {
            return recordingManager.currentDuration
        } else if connectivity.phoneIsRecording {
            return phoneRecordingDuration
        }
        return 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Spacer()

                // Status area above the button
                if isRecording {
                    VStack(spacing: 4) {
                        // Phone recording indicator
                        if connectivity.phoneIsRecording {
                            HStack(spacing: 4) {
                                Image(systemName: "iphone")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Text("iPhone")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Timer
                        Text(formatDuration(currentDuration))
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())

                        // Long recording warning
                        if recordingManager.isRecording
                            && recordingManager.currentDuration >= 30 * 60
                        {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Long recording")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .transition(.opacity)
                }

                // Record button, with discard tucked to its left while this watch
                // is the one recording. Same arrangement as the iPhone controls, so
                // the two apps read the same way. A phone recording is the phone's
                // to cancel.
                // On save the whole button becomes the confirmation, rather than a
                // checkmark laid over a record button that now means something else.
                if showSaved {
                    savedConfirmation
                } else {
                    ZStack {
                        WatchRecordButtonView(
                            isRecording: isRecording,
                            audioLevel: recordingManager.audioLevel
                        ) {
                            Task {
                                await toggleRecording()
                            }
                        }

                        if recordingManager.isRecording {
                            HStack {
                                Button {
                                    if recordingManager.currentDuration > 30 {
                                        showCancelConfirmation = true
                                    } else {
                                        cancelRecording()
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 26, height: 26)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Discard recording")

                                Spacer()
                            }
                            .transition(.opacity)
                        }
                    }
                }



                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: isRecording)
            .animation(.easeInOut(duration: 0.2), value: showSaved)
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: WatchRecordingsListView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "list.bullet")
                            if syncQueue.pendingCount > 0 {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Discard recording?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { cancelRecording() }
            Button("Keep Recording", role: .cancel) {}
        }
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

    /// Occupies the record button's exact footprint, so the control doesn't shift
    /// and the confirmation reads as that button having completed.
    private var savedConfirmation: some View {
        ZStack {
            Circle()
                .stroke(Color.green, lineWidth: 4)
                .frame(width: 80, height: 80)
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.green)
        }
        .frame(width: 88, height: 88)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .accessibilityLabel("Saved")
    }

    private func showSavedConfirmation() async {
        showSaved = true
        try? await Task.sleep(nanoseconds: 900_000_000)
        showSaved = false
    }

    private func cancelRecording() {
        WatchHapticService.recordStop()
        recordingManager.cancelRecording()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    WatchMainView()
}
