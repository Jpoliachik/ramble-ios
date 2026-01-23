//
//  WatchMainView.swift
//  watch Watch App
//

import SwiftUI

struct WatchMainView: View {
    @StateObject private var audioRecorder = WatchAudioRecorderService()
    @StateObject private var connectivity = WatchConnectivityService.shared

    @State private var showSaved = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Status indicator
            statusView

            // Timer
            Text(formatDuration(audioRecorder.currentDuration))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundColor(audioRecorder.isRecording ? .red : .secondary)

            Spacer()

            // Record button
            WatchRecordButtonView(isRecording: audioRecorder.isRecording) {
                Task {
                    await toggleRecording()
                }
            }

            Spacer()
        }
        .padding()
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
        } else {
            Text("Ramble")
                .font(.headline)
        }
    }

    private func toggleRecording() async {
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
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopAndTransfer() async {
        guard let result = audioRecorder.stopRecording() else { return }

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
