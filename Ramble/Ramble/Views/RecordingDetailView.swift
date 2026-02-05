//
//  RecordingDetailView.swift
//  Ramble
//

import Combine
import SwiftUI

struct RecordingDetailView: View {
    let recordingId: UUID
    @State private var recording: Recording?
    @State private var showCopied = false
    @State private var isRetryingWebhook = false
    @State private var isRetryingTranscription = false
    @State private var now = Date()

    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared
    private let webhookService = WebhookService.shared

    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .onReceive(NotificationCenter.default.publisher(for: StorageService.recordingsDidChangeNotification)) { _ in
            refreshRecording()
        }
        .onReceive(countdownTimer) { date in
            now = date
        }
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

            if let noSpeechProb = recording.noSpeechProbability {
                HStack {
                    Label("Quality", systemImage: "waveform.badge.checkmark")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    qualityBadge(noSpeechProb: noSpeechProb)
                }
            }

            if let language = recording.transcriptionLanguage {
                HStack {
                    Label("Language", systemImage: "globe")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(language.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

    private func qualityBadge(noSpeechProb: Double) -> some View {
        let quality = 1.0 - noSpeechProb
        let (label, color): (String, Color) = {
            if quality >= 0.7 { return ("Good", .green) }
            if quality >= 0.4 { return ("Fair", .orange) }
            return ("Poor", .red)
        }()

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
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

            if isTranscribing(recording) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(transcriptionProgressLabel(for: recording))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Transcription retry countdown
            if recording.transcriptionStatus == .pending,
               let job = transcriptionQueue.transcriptionJob(for: recording.id),
               job.retryCount > 0,
               let nextRetry = job.nextRetryAt {
                retryCountdownBanner(
                    nextRetryAt: nextRetry,
                    retryCount: job.retryCount,
                    maxRetries: TranscriptionJob.maxRetries,
                    label: "transcription"
                )
            }

            if recording.transcriptionStatus == .failed, let error = recording.lastTranscriptionError {
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
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    refreshRecording()
                    isRetryingTranscription = false
                }
            } label: {
                HStack {
                    if isRetryingTranscription {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(retranscribeButtonLabel(for: recording))
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRetryingTranscription || isTranscribing(recording))
        }
    }

    private func isTranscribing(_ recording: Recording) -> Bool {
        [.uploading, .processing].contains(recording.transcriptionStatus)
    }

    private func transcriptionProgressLabel(for recording: Recording) -> String {
        switch recording.transcriptionStatus {
        case .uploading: return "Uploading audio..."
        case .processing: return "Transcribing..."
        default: return "Processing..."
        }
    }

    private func retranscribeButtonLabel(for recording: Recording) -> String {
        switch recording.transcriptionStatus {
        case .failed: return "Retry Transcription"
        case .completed: return "Re-transcribe"
        case .pending: return "Force Retry"
        default: return "Transcribing..."
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

    // MARK: - Webhook Section

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
                    NavigationLink(destination: WebhookAttemptDetailView(attempt: attempt)) {
                        webhookAttemptRow(attempt)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Webhook retry status
            webhookRetryStatus(recording)

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

    @ViewBuilder
    private func webhookRetryStatus(_ recording: Recording) -> some View {
        let lastFailed = recording.webhookAttempts.last.map { !$0.success } ?? false

        if lastFailed && recording.webhookRetriesExhausted {
            retryStatusBanner(
                icon: "xmark.circle",
                text: "All automatic retries exhausted",
                color: .red
            )
        } else if lastFailed && recording.webhookRetryCount > Recording.maxInAppWebhookRetries {
            retryStatusBanner(
                icon: "clock.arrow.circlepath",
                text: "Will retry in background",
                color: .orange
            )
        } else if let nextRetry = recording.nextWebhookRetryAt, lastFailed {
            retryCountdownBanner(
                nextRetryAt: nextRetry,
                retryCount: recording.webhookRetryCount,
                maxRetries: Recording.maxTotalWebhookRetries,
                label: "webhook"
            )
        }
    }

    // MARK: - Retry UI Components

    private func retryCountdownBanner(
        nextRetryAt: Date,
        retryCount: Int,
        maxRetries: Int,
        label: String
    ) -> some View {
        let remaining = max(0, Int(nextRetryAt.timeIntervalSince(now)))

        return HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .foregroundColor(.orange)
            if remaining > 0 {
                Text("Auto-retrying \(label) in \(remaining)s (attempt \(retryCount + 1)/\(maxRetries))")
            } else {
                Text("Retrying \(label)...")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func retryStatusBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Webhook Attempt Row

    private func webhookAttemptRow(_ attempt: WebhookAttempt) -> some View {
        HStack(spacing: 10) {
            Image(systemName: attempt.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(attempt.success ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(attempt.success ? "Sent" : "Failed")
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(DateFormatters.timeFormatter.string(from: attempt.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let durationMs = attempt.durationMs {
                Text(formatDurationMs(durationMs))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    private func formatDurationMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
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
            transcription: "This is a sample transcription.",
            transcriptionStatus: .completed,
            webhookAttempts: [
                WebhookAttempt(url: "https://example.com/webhook", success: true, statusCode: 200, durationMs: 234),
                WebhookAttempt(url: "https://example.com/webhook", success: false, statusCode: 500, errorMessage: "Internal Server Error", durationMs: 1523)
            ]
        ))
    }
}
