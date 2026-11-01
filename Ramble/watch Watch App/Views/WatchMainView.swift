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

    @Environment(\.scenePhase) private var scenePhase

    @State private var showSaved = false
    @State private var startFailed = false
    @State private var phoneRecordingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    @State private var stopRequestCancellable: AnyCancellable?

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
                Spacer(minLength: 0)

                WatchRecordButtonView(
                    isRecording: isRecording,
                    audioLevel: recordingManager.audioLevel
                ) {
                    Task {
                        await toggleRecording()
                    }
                }

                // Fixed height so the button never moves when the status changes
                statusArea
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)

                Spacer(minLength: 0)
            }
            .animation(.easeInOut(duration: 0.3), value: isRecording)
            .animation(.easeInOut(duration: 0.2), value: showSaved)
            .animation(.easeInOut(duration: 0.2), value: startFailed)
        }
        .onAppear {
            subscribeToStopRequests()
            refreshOnForeground()
        }
        .onDisappear {
            stopRequestCancellable?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshOnForeground()
            }
        }
        .onChange(of: connectivity.phoneIsRecording) { _, isRecording in
            if isRecording {
                startPhoneDurationTimer()
            } else {
                stopPhoneDurationTimer()
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusArea: some View {
        if isRecording {
            VStack(spacing: 2) {
                Text(WatchFormat.duration(currentDuration))
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.brandRed)
                    .contentTransition(.numericText())

                if connectivity.phoneIsRecording {
                    statusLine("Recording on iPhone", symbol: "iphone", tint: .secondary)
                } else if recordingManager.currentDuration >= 30 * 60 {
                    statusLine("Long recording", symbol: "clock", tint: .orange)
                }
            }
            .transition(.opacity)
        } else if startFailed {
            statusLine("Couldn't start recording", symbol: "mic.slash", tint: .orange)
                .transition(.opacity)
        } else if showSaved {
            statusLine("Saved on watch", symbol: "checkmark.circle", tint: .secondary)
                .transition(.opacity)
        } else if let summary = idleSummary {
            NavigationLink {
                WatchRecordingsListView()
            } label: {
                HStack(spacing: 4) {
                    statusLine(summary.label, symbol: summary.symbol, tint: summary.tint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        } else {
            Text("Tap to record")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// One line describing the latest recording, or the backlog if older ones are still waiting.
    private var idleSummary: (label: String, symbol: String, tint: Color)? {
        guard let latest = history.entries.first else { return nil }

        let latestState = state(for: latest)
        let pendingCount = syncQueue.jobs.count

        if pendingCount == 0 || (pendingCount == 1 && latestState.isPending) {
            return (latestState.label, latestState.symbol, latestState.tint)
        }

        let anyRetrying = syncQueue.jobs.contains { job in
            job.retryCount > 0 && !connectivity.inFlightIDs.contains(job.id)
        }
        return (
            "\(pendingCount) waiting to send",
            anyRetrying ? "arrow.clockwise.circle" : "arrow.up.circle",
            anyRetrying ? Color.orange : Color.secondary
        )
    }

    private func state(for entry: WatchRecordingHistoryEntry) -> WatchRecordingState {
        WatchRecordingState.resolve(
            entry: entry,
            job: syncQueue.jobs.first { $0.id == entry.id },
            isInFlight: connectivity.inFlightIDs.contains(entry.id),
            isPhoneReachable: connectivity.isPhoneReachable
        )
    }

    private func statusLine(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .font(.caption2)
        .foregroundStyle(tint)
    }

    // MARK: - Actions

    private func refreshOnForeground() {
        connectivity.queryPhoneState()
        // Retry anything still waiting, including transfers from previous sessions
        syncQueue.pruneOrphanedJobs()
        connectivity.retryPendingTransfers()
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
            showSaved = false
            startFailed = false
            WatchHapticService.recordStart()
            if !recordingManager.startRecording() {
                WatchHapticService.failure()
                await showStartFailure()
            }
        }
    }

    private func showSavedConfirmation() async {
        showSaved = true
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        showSaved = false
    }

    private func showStartFailure() async {
        startFailed = true
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        startFailed = false
    }
}

#Preview {
    WatchMainView()
}
