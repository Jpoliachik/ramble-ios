//
//  RecordingDetailView.swift
//  Ramble
//

import SwiftUI

struct RecordingDetailView: View {
    let recordingId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var recording: Recording?
    @State private var showCopied = false
    @State private var isRetrying = false
    @State private var isDownloadingModel = false
    @State private var showDeleteConfirmation = false
    @State private var isResendingWebhook = false
    @State private var isTranscriptExpanded = false
    @State private var transcriptFullHeight: CGFloat = 0
    @State private var transcriptLimitedHeight: CGFloat = 0

    private var isTranscriptTruncated: Bool {
        transcriptFullHeight > transcriptLimitedHeight + 1
    }

    private let storageService = StorageService.shared
    private let transcriptionQueue = TranscriptionQueueService.shared

    init(recording: Recording) {
        self.recordingId = recording.id
        self._recording = State(initialValue: recording)
    }

    var body: some View {
        Group {
            if let recording = recording {
                Form {
                    headerSection(recording)
                    transcriptSection(recording)
                    audioSection(recording)
                    actionsSection(recording)
                    if !recording.activityLog.isEmpty {
                        activitySection(recording)
                    }
                }
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Recording", role: .destructive) {
                if let recording = recording {
                    storageService.deleteRecording(recording)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the recording and its transcript.")
        }
        .overlay(alignment: .top) {
            if showCopied {
                copiedToast
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
        #if DEBUG
        if MockDataProvider.enabled { return }
        #endif
        let recordings = storageService.loadRecordings()
        recording = recordings.first { $0.id == recordingId }
    }

    // MARK: - Header

    private func headerSection(_ recording: Recording) -> some View {
        Section {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateFormatters.formatDuration(recording.duration))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("\(DateFormatters.dayFormatter.string(from: recording.createdAt)) at \(DateFormatters.timeFormatter.string(from: recording.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(for: recording)
            }
        }
    }

    private func statusBadge(for recording: Recording) -> some View {
        HStack(spacing: 4) {
            switch recording.status {
            case .recorded:
                if recording.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Retrying")
                } else {
                    Image(systemName: "clock")
                    Text("Queued")
                }
            case .transcribing:
                ProgressView().scaleEffect(0.7)
                Text("Transcribing")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                Text("Completed")
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                Text("Failed")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(statusColor(for: recording))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor(for: recording).opacity(0.12))
        .clipShape(.capsule)
    }

    private func statusColor(for recording: Recording) -> Color {
        switch recording.status {
        case .recorded: return recording.lastError != nil ? .orange : .secondary
        case .transcribing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    // MARK: - Audio

    private func audioSection(_ recording: Recording) -> some View {
        Section {
            #if DEBUG
            if MockDataProvider.enabled {
                MockAudioPlayerView(recording: recording)
            } else if FileManager.default.fileExists(atPath: recording.audioFileURL.path) {
                AudioPlayerView(audioURL: recording.audioFileURL)
            } else {
                Label("Audio file not available", systemImage: "waveform.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            #else
            if FileManager.default.fileExists(atPath: recording.audioFileURL.path) {
                AudioPlayerView(audioURL: recording.audioFileURL)
            } else {
                Label("Audio file not available", systemImage: "waveform.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }

    // MARK: - Transcript

    private func transcriptSection(_ recording: Recording) -> some View {
        Section {
            if let transcription = recording.transcription, !transcription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(transcription)
                        .font(.body)
                        .lineLimit(isTranscriptExpanded ? nil : 12)
                        .textSelection(.enabled)
                        .background {
                            ZStack(alignment: .topLeading) {
                                Text(transcription)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(heightReader($transcriptFullHeight))
                                Text(transcription)
                                    .font(.body)
                                    .lineLimit(12)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(heightReader($transcriptLimitedHeight))
                            }
                            .hidden()
                        }

                    if isTranscriptTruncated {
                        Button {
                            withAnimation { isTranscriptExpanded.toggle() }
                        } label: {
                            Text(isTranscriptExpanded ? "Show less" : "Show more")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else if recording.status == .transcribing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Transcribing...")
                        .foregroundStyle(.secondary)
                }
            } else if recording.isModelNotInstalled {
                modelNotInstalledView
            } else if let error = recording.lastError, !error.isEmpty {
                errorView(error, isFailed: recording.status == .failed)
            } else {
                Text(transcriptPlaceholder(for: recording))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        } header: {
            HStack {
                Text("Transcript")
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
                        Label("Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
        }
    }

    private func errorView(_ error: String, isFailed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(isFailed ? "Error" : "Retrying", systemImage: isFailed ? "xmark.circle" : "arrow.clockwise")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isFailed ? .red : .orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelNotInstalledView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Speech Model Required", systemImage: "arrow.down.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            Text("The on-device speech model needs to be downloaded before transcription can work.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func actionsSection(_ recording: Recording) -> some View {
        Section {
            if recording.isModelNotInstalled {
                Button {
                    HapticService.buttonTap()
                    isDownloadingModel = true
                    Task {
                        do {
                            try await transcriptionQueue.downloadModelAndRetryPending()
                        } catch {
                            print("Model download failed: \(error)")
                        }
                        refreshRecording()
                        isDownloadingModel = false
                    }
                } label: {
                    Label {
                        Text(isDownloadingModel ? "Downloading..." : "Download Speech Model & Retry")
                    } icon: {
                        if isDownloadingModel {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
                .disabled(isDownloadingModel)
            } else {
                let cloudLimitReached = SettingsService.shared.load().transcriptionProvider.isCloud
                    && recording.cloudTranscriptionCount >= TranscriptionJob.maxCloudTranscriptions

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
                    Label {
                        Text(retryButtonLabel(for: recording))
                    } icon: {
                        if isRetrying {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(isRetrying || recording.status == .transcribing || cloudLimitReached)

                if cloudLimitReached {
                    Text("Cloud transcription limit reached (\(TranscriptionJob.maxCloudTranscriptions)). Switch to on-device transcription in Settings to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if recording.webhookStatus != nil && SettingsService.shared.load().webhookEnabled {
                Button {
                    HapticService.buttonTap()
                    isResendingWebhook = true
                    WebhookQueueService.shared.enqueue(recordingId: recording.id)
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        refreshRecording()
                        isResendingWebhook = false
                    }
                } label: {
                    Label {
                        Text(isResendingWebhook ? "Sending..." : "Resend Webhook")
                    } icon: {
                        if isResendingWebhook {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane")
                        }
                    }
                }
                .disabled(isResendingWebhook || recording.webhookStatus == .sending)
            }
        }
    }

    // MARK: - Activity

    private func activitySection(_ recording: Recording) -> some View {
        Section("Activity") {
            ForEach(Array(recording.activityLog.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 10) {
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let status = entry.httpStatus {
                        Text("\(status)")
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(status < 300 ? .green : .red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((status < 300 ? Color.green : Color.red).opacity(0.12))
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    Text(DateFormatters.timeFormatter.string(from: entry.timestamp))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func retryButtonLabel(for recording: Recording) -> String {
        switch recording.status {
        case .failed: return "Retry Transcription"
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
        case .failed: return "Transcription failed."
        }
    }

    private func heightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { binding.wrappedValue = proxy.size.height }
                .onChange(of: proxy.size.height) { _, newValue in
                    binding.wrappedValue = newValue
                }
        }
    }

    private var copiedToast: some View {
        Label("Copied", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .capsule)
            .shadow(radius: 4)
            .padding(.top, 8)
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: Recording(
            duration: 125,
            status: .completed,
            transcription: "This is a sample transcription that shows what the text might look like after recording.",
            activityLog: [
                ActivityEntry("Transcription completed (342 chars)", httpStatus: 200),
                ActivityEntry("Webhook delivered", httpStatus: 200),
            ]
        ))
    }
}
