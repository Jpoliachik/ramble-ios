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
    @State private var showDetails = false
    @State private var isTranscriptExpanded = false
    @State private var transcriptFullHeight: CGFloat = 0
    @State private var transcriptLimitedHeight: CGFloat = 0
    @State private var showConnectAgent = false
    @ObservedObject private var relay = RelayService.shared

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
                    deliverySection(recording)
                    if !recording.activityLog.isEmpty {
                        activitySection(recording)
                    }
                }
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let recording {
                    moreMenu(recording)
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
        .sheet(isPresented: $showConnectAgent) {
            ConnectAgentView(startPairing: true)
        }
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
        let stage = DeliveryStage(recording)
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateFormatters.formatDuration(recording.duration))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("\(DateFormatters.dayFormatter.string(from: recording.createdAt)) at \(DateFormatters.timeFormatter.string(from: recording.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                StatusPill(text: stage.label, dot: stage.tint)
            }
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

    // MARK: - Delivery

    private enum DeliveryAction {
        case retryTranscription, downloadModel, resend, connect

        var title: String {
            switch self {
            case .retryTranscription, .resend: return "Retry"
            case .downloadModel: return "Download"
            case .connect: return "Connect"
            }
        }
    }

    private struct DeliveryLine {
        var title: String
        var detail: String?
        var action: DeliveryAction?
    }

    private var cloudLimitReached: Bool {
        guard let recording else { return false }
        return SettingsService.shared.load().transcriptionProvider.isCloud
            && recording.cloudTranscriptionCount >= TranscriptionJob.maxCloudTranscriptions
    }

    private func deliveryLine(for recording: Recording) -> DeliveryLine {
        let sentAt = recording.relayUploadedAt.map { DateFormatters.timeFormatter.string(from: $0) }
        switch DeliveryStage(recording) {
        case .transcribing:
            if recording.status == .recorded, let error = recording.lastError, !error.isEmpty {
                return DeliveryLine(title: "Transcribing…", detail: "\(error) Ramble will try again on its own.")
            }
            return DeliveryLine(title: "Transcribing…", detail: "It goes out as soon as the transcript is ready.")
        case .couldntTranscribe(needsModel: true):
            return DeliveryLine(
                title: "Speech model needed",
                detail: "Download the on-device model to transcribe this note.",
                action: .downloadModel
            )
        case .couldntTranscribe(needsModel: false):
            if cloudLimitReached {
                return DeliveryLine(
                    title: "Couldn't transcribe",
                    detail: "Cloud transcription limit reached (\(TranscriptionJob.maxCloudTranscriptions)). Switch to on-device transcription in Settings to continue."
                )
            }
            return DeliveryLine(title: "Couldn't transcribe", detail: recording.lastError, action: .retryTranscription)
        case .onPhone:
            if relay.hasConnectedAgents || SettingsService.shared.load().isWebhookConfigured {
                return DeliveryLine(title: "Not sent", detail: "It was made before anywhere was set up to send it.", action: .resend)
            }
            return DeliveryLine(title: "Only on this iPhone", detail: "Connect an agent to send it.", action: .connect)
        case .sending:
            return DeliveryLine(title: "Sending…")
        case .waitingForAgent:
            return DeliveryLine(
                title: "Sent, not picked up yet",
                detail: [sentAt.map { "Sent \($0)." }, "Your agent picks it up next time it checks."]
                    .compactMap { $0 }.joined(separator: " ")
            )
        case .agentHasIt:
            let pickedUp = recording.pickedUpAt.map { "picked up \(DateFormatters.timeFormatter.string(from: $0))" }
            let detail = [sentAt.map { "Sent \($0)" }, pickedUp].compactMap { $0 }.joined(separator: " · ")
            return DeliveryLine(title: "Picked up by your agent", detail: detail.isEmpty ? nil : detail)
        case .deliveredToWebhook:
            return DeliveryLine(title: "Delivered to webhook")
        case .didntSend:
            let relayFailed = recording.relayStatus == .failed
            if relayFailed && !relay.hasConnectedAgents {
                return DeliveryLine(title: "No agent to send it to", detail: "Connect an agent to send it.", action: .connect)
            }
            return DeliveryLine(
                title: relayFailed ? "Couldn't reach your agent" : "Webhook didn't accept it",
                detail: recording.lastError,
                action: .resend
            )
        }
    }

    private func deliverySection(_ recording: Recording) -> some View {
        let line = deliveryLine(for: recording)
        return Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(.body.weight(.medium))
                    if let detail = line.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let action = line.action {
                    Button {
                        perform(action, for: recording)
                    } label: {
                        if isRetrying || isDownloadingModel {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(action.title)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.brandAmber)
                    .controlSize(.small)
                    .disabled(isRetrying || isDownloadingModel)
                }
            }
        }
    }

    private func perform(_ action: DeliveryAction, for recording: Recording) {
        HapticService.buttonTap()
        switch action {
        case .connect:
            showConnectAgent = true
        case .retryTranscription:
            retryTranscription(recording)
        case .downloadModel:
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
        case .resend:
            resend(recording)
        }
    }

    private func retryTranscription(_ recording: Recording) {
        isRetrying = true
        Task {
            // Covers recordings made on the Watch, where no phone-side
            // recording start ever prompted for speech recognition
            await LegacySpeechTranscriptionService.requestAuthorizationIfNeeded()
            transcriptionQueue.retry(recordingId: recording.id)
            try? await Task.sleep(nanoseconds: 500_000_000)
            refreshRecording()
            isRetrying = false
        }
    }

    /// Sends again to whichever destinations it should go to: the failed
    /// ones, or every set-up one for a note that was never sent.
    private func resend(_ recording: Recording) {
        let neverSent = recording.deliveryStatus == nil
        let webhookSetUp = SettingsService.shared.load().isWebhookConfigured
        if webhookSetUp && (recording.webhookStatus == .failed || neverSent) {
            WebhookQueueService.shared.resend(recordingId: recording.id)
        }
        if relay.hasConnectedAgents && (recording.relayStatus == .failed || neverSent) {
            RelayQueueService.shared.resend(recordingId: recording.id)
        }
        isRetrying = true
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            refreshRecording()
            isRetrying = false
        }
    }

    // MARK: - More menu

    private func moreMenu(_ recording: Recording) -> some View {
        Menu {
            if !recording.isModelNotInstalled {
                Button {
                    HapticService.buttonTap()
                    retryTranscription(recording)
                } label: {
                    Label(retryButtonLabel(for: recording), systemImage: "arrow.clockwise")
                }
                .disabled(isRetrying || recording.status == .transcribing || cloudLimitReached)
            }

            if recording.status == .completed && relay.hasConnectedAgents
                && recording.relayStatus != .sending && recording.relayStatus != .pending {
                Button {
                    HapticService.buttonTap()
                    RelayQueueService.shared.resend(recordingId: recording.id)
                } label: {
                    Label(recording.relayStatus == nil ? "Send to Agent" : "Send to Agent Again", systemImage: "arrow.up.circle")
                }
            }

            if recording.webhookStatus != nil && recording.webhookStatus != .sending
                && SettingsService.shared.load().isWebhookConfigured {
                Button {
                    HapticService.buttonTap()
                    WebhookQueueService.shared.resend(recordingId: recording.id)
                } label: {
                    Label("Resend Webhook", systemImage: "paperplane")
                }
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    // MARK: - Activity

    /// The raw log, folded away. Handy when something goes wrong.
    private func activitySection(_ recording: Recording) -> some View {
        Section {
            DisclosureGroup("Details", isExpanded: $showDetails) {
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
                        Text(DateFormatters.timeWithSecondsFormatter.string(from: entry.timestamp))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
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
        case .failed: return "No transcript yet."
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
