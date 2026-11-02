//
//  WatchMainView.swift
//  watch Watch App
//

import SwiftUI

struct WatchMainView: View {
    @StateObject private var recordingManager = WatchRecordingManager.shared
    @StateObject private var connectivity = WatchConnectivityService.shared
    @StateObject private var syncQueue = WatchSyncQueue.shared
    @StateObject private var history = WatchRecordingHistory.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var showSaved = false
    /// Set while a start failure is on screen; the text says what went wrong.
    @State private var startFailureMessage: String?
    /// Ignores extra taps while the mic permission prompt or session setup is pending.
    @State private var isStarting = false

    private var isRecording: Bool {
        recordingManager.isRecording
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // While recording, a tap anywhere stops. The button stays the
                // accessible control and keeps the double-tap shortcut.
                if isRecording {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            Task {
                                await toggleRecording()
                            }
                        }
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isRecording)
            .animation(.easeInOut(duration: 0.2), value: showSaved)
            .animation(.easeInOut(duration: 0.2), value: startFailureMessage)
        }
        .onAppear {
            refreshOnForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshOnForeground()
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusArea: some View {
        if isRecording {
            VStack(spacing: 2) {
                Text(WatchFormat.duration(recordingManager.currentDuration))
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.brandAmber)
                    .contentTransition(.numericText())

                if recordingManager.currentDuration >= 30 * 60 {
                    statusLine("Long recording", symbol: "clock", tint: .orange)
                }
            }
            .transition(.opacity)
        } else if let startFailureMessage {
            statusLine(startFailureMessage, symbol: "mic.slash", tint: .orange)
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

        // Waiting and retrying are normal; the watch keeps the audio until the phone has it.
        return ("\(pendingCount) on watch, will send", "applewatch", Color.secondary)
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
        // Retry anything still waiting, including transfers from previous sessions
        syncQueue.pruneOrphanedJobs()
        connectivity.retryPendingTransfers()
    }

    /// A tap always records on the watch, whatever the phone is doing.
    private func toggleRecording() async {
        if recordingManager.isRecording {
            WatchHapticService.recordStop()
            recordingManager.stopRecordingAndTransfer()
            await showSavedConfirmation()
        } else {
            guard !isStarting else { return }
            isStarting = true
            defer { isStarting = false }
            showSaved = false
            startFailureMessage = nil
            if await recordingManager.startRecording() {
                WatchHapticService.recordStart()
            } else {
                WatchHapticService.failure()
                await showStartFailure(
                    recordingManager.isMicrophoneDenied
                        ? "Allow microphone in Settings"
                        : "Couldn't start recording"
                )
            }
        }
    }

    private func showSavedConfirmation() async {
        showSaved = true
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        showSaved = false
    }

    private func showStartFailure(_ message: String) async {
        startFailureMessage = message
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if startFailureMessage == message {
            startFailureMessage = nil
        }
    }
}

#Preview {
    WatchMainView()
}
