//
//  RecordingDetailView.swift
//  Ramble
//

import SwiftUI

struct RecordingDetailView: View {
    let recordingId: UUID
    @State private var recording: Recording?
    @State private var showCopied = false
    @State private var isRetryingWebhook = false
    @State private var isRetryingTranscription = false

    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared
    private let webhookService = WebhookService.shared

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

                    if webhookService.isWebhookConfigured {
                        Divider()
                        webhookSection(recording)
                    }
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
    }

    private func refreshRecording() {
        let recordings = storageService.loadRecordings()
        recording = recordings.first { $0.id == recordingId }
    }

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
            switch recording.transcriptionStatus {
            case .pending:
                Image(systemName: "clock")
                Text("Pending")
            case .uploading:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Uploading")
            case .processing:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Processing")
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

            if recording.transcriptionStatus == .failed {
                if let error = recording.lastTranscriptionError {
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

                Button {
                    HapticService.buttonTap()
                    isRetryingTranscription = true
                    transcriptionQueue.retryTranscription(for: recording.id)
                    refreshRecording()
                    isRetryingTranscription = false
                } label: {
                    HStack {
                        if isRetryingTranscription {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Retry Transcription")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRetryingTranscription)
            }
        }
    }

    private func transcriptPlaceholder(for recording: Recording) -> String {
        switch recording.transcriptionStatus {
        case .pending:
            return "Transcription pending..."
        case .uploading:
            return "Uploading audio..."
        case .processing:
            return "Transcribing..."
        case .completed:
            return "No transcription available."
        case .failed:
            return "Transcription failed. Please try again."
        }
    }

    private func webhookSection(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Webhook")
                .font(.headline)

            if recording.webhookAttempts.isEmpty {
                Text("No webhook attempts yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(recording.webhookAttempts) { attempt in
                    webhookAttemptRow(attempt)
                }
            }

            Button {
                HapticService.buttonTap()
                isRetryingWebhook = true
                Task {
                    await transcriptionQueue.retryWebhook(for: recording.id)
                    refreshRecording()
                    isRetryingWebhook = false
                }
            } label: {
                HStack {
                    if isRetryingWebhook {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(recording.webhookAttempts.isEmpty ? "Send Webhook" : "Retry Webhook")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRetryingWebhook)
        }
    }

    private func webhookAttemptRow(_ attempt: WebhookAttempt) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attempt.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(attempt.success ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(attempt.url)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(DateFormatters.timeFormatter.string(from: attempt.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let statusCode = attempt.statusCode {
                        Text("HTTP \(statusCode)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let error = attempt.errorMessage, !attempt.success {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
            transcription: "This is a sample transcription.",
            transcriptionStatus: .completed,
            webhookAttempts: [
                WebhookAttempt(url: "https://example.com/webhook", success: true, statusCode: 200),
                WebhookAttempt(url: "https://example.com/webhook", success: false, statusCode: 500)
            ]
        ))
    }
}
