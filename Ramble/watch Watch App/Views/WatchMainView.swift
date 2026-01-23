//
//  WatchMainView.swift
//  watch Watch App
//

import Combine
import SwiftUI

struct WatchMainView: View {
    @StateObject private var audioRecorder = WatchAudioRecorderService()
    @StateObject private var connectivity = WatchConnectivityService.shared

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
            WatchRecordButtonView(isRecording: audioRecorder.isRecording || connectivity.phoneIsRecording) {
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
                    .foregroundColor(.green)
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
        } else if connectivity.phoneIsRecording {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.red)
                Text("Recording")
                    .font(.caption)
            }
        } else {
            Text("Ramble")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var timerView: some View {
        if audioRecorder.isRecording {
            Text(formatDuration(audioRecorder.currentDuration))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundColor(.red)
        } else if connectivity.phoneIsRecording {
            Text(formatDuration(phoneRecordingDuration))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundColor(.red)
        } else {
            Text(formatDuration(0))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
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
        guard audioRecorder.isRecording else { return }
        WatchHapticService.recordStop()
        await stopAndTransfer()
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
        // If phone is recording, stop it instead of starting watch recording
        if connectivity.phoneIsRecording {
            WatchHapticService.recordStop()
            connectivity.requestPhoneStopRecording()
            return
        }

        if audioRecorder.isRecording {
            WatchHapticService.recordStop()
            await stopAndTransfer()
        } else {
            WatchHapticService.recordStart()
            await startRecording()
        }
    }

    private func startRecording() async {
        do {
            _ = try await audioRecorder.startRecording()
            connectivity.sendRecordingStarted()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopAndTransfer() async {
        guard let result = audioRecorder.stopRecording() else { return }
        connectivity.sendRecordingStopped()

        showSaved = true

        connectivity.transferRecording(url: result.url, duration: result.duration)

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
