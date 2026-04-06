//
//  RecordingDetailView.swift
//  Ramble
//

import SwiftUI

struct RecordingDetailView: View {
    let recordingId: UUID
    @State private var recording: Recording?
    @State private var showCopied = false
    @State private var isRetrying = false

    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared

    init(recording: Recording) {
        self.recordingId = recording.id
        self._recording = State(initialValue: recording)
    }

    var body: some View {
        ScrollView {
            if let recording = recording {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection(recording)
                    Divider()
                    transcriptSection(recording)
                }
                .padding()
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if showCopied {
                copiedConfirmation
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopied)
        .onAppear { refreshRecording() }
        .onReceive(NotificationCenter.default.publisher(for: StorageService.recordingsDidChangeNotification)) { _ in
            refreshRecording()
        }
    }

    private func refreshRecording() {
        let recordings = storageService.loadRecordings()
        recording = recordings.first { $0.id == recordingId }
    }

    // MARK: - Metadata Section

    private func metadataSection(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    DateFormatters.dayFormatter.string(from: recording.createdAt),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                Spacer()

                Label(
                    DateFormatters.timeFormatter.string(from: recording.createdAt),
                    systemImage: "clock"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            HStack {
                Label(
                    DateFormatters.formatDuration(recording.duration),
                    systemImage: "waveform"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                Spacer()

                statusBadge(for: recording)
            }
        }
    }

    private func statusBadge(for recording: Recording) -> some View {
        HStack(spacing: 4) {
            switch recording.status {
            case .recorded:
                Image(systemName: "clock")
                Text("Recorded")
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Transcribing")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Completed")
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text("Failed")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Transcript Section

    private func transcriptSection(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                if let transcription = recording.transcription, !transcription.isEmpty {
                    Button {
                        HapticService.buttonTap()
                        UIPasteboard.general.string = transcription
                        showCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            showCopied = false
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                }
            }

            if let transcription = recording.transcription, !transcription.isEmpty {
                Text(transcription)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Text(transcriptPlaceholder(for: recording))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }

            if recording.status == .transcribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            if recording.status == .failed, let error = recording.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Webhook status
            if let webhookStatus = recording.webhookStatus {
                webhookStatusView(webhookStatus)
            }

            Button {
                HapticService.buttonTap()
                isRetrying = true
                transcriptionQueue.retry(recordingId: recording.id)
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    refreshRecording()
                    isRetrying = false
                }
            } label: {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(retryButtonLabel(for: recording))
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRetrying || recording.status == .transcribing)
        }
    }

    // MARK: - Webhook Status

    private func webhookStatusView(_ status: WebhookStatus) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .pending, .sending:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Sending to webhook...")
            case .delivered:
                Image(systemName: "paperplane.circle.fill")
                    .foregroundColor(.green)
                Text("Webhook delivered")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Webhook failed")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func retryButtonLabel(for recording: Recording) -> String {
        switch recording.status {
        case .failed: return "Retry"
        case .completed: return "Re-transcribe"
        case .recorded: return "Transcribe"
        default: return "Transcribing..."
        }
    }

    private func transcriptPlaceholder(for recording: Recording) -> String {
        switch recording.status {
        case .recorded: return "Waiting to transcribe..."
        case .transcribing: return "Transcribing..."
        case .completed: return "No transcription available."
        case .failed: return "Transcription failed. Tap Retry below."
        }
    }

    private var copiedConfirmation: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Copied")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(radius: 4)
        )
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: Recording(
            duration: 125,
            status: .completed,
            transcription: "This is a sample transcription."
        ))
    }
}
