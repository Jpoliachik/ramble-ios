//
//  RecordingDetailView.swift
//  Ramble
//
//  The note screen (specs/phone.md "Note screen"): header, transcript,
//  playback, the one delivery line, and the More menu.
//

import SwiftUI

struct RecordingDetailView: View {
    let recordingId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var recording: Recording?
    @State private var showCopied = false
    @State private var showDeleteConfirmation = false
    @State private var isTranscriptExpanded = false
    @State private var transcriptFullHeight: CGFloat = 0
    @State private var transcriptLimitedHeight: CGFloat = 0
    @State private var showUnlock = false
    @State private var audioRequest: AudioRequest = .idle
    @State private var shareURL: URL?
    @ObservedObject private var relay = RelayService.shared

    private enum AudioRequest {
        case idle
        case asking
        /// The watch app isn't open, which only the person can change.
        case openWatch
    }

    private var isTranscriptTruncated: Bool {
        transcriptFullHeight > transcriptLimitedHeight + 1
    }

    private let storageService = StorageService.shared

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
                .readableListWidth()
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
        .task(id: recording?.hasAudio) {
            guard let recording, recording.hasAudio else {
                shareURL = nil
                return
            }
            shareURL = Self.shareableCopy(of: recording.audioFileURL, named: Self.shareFileName(for: recording))
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
        .sheet(isPresented: $showUnlock) {
            UnlockSheet()
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
        recording = storageService.recording(withId: recordingId)
        if recording?.hasAudio == true { audioRequest = .idle }
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
                StatusPill(text: stage.label(for: recording), dot: stage.tint(for: recording))
            }
        }
    }

    // MARK: - Transcript

    private func transcriptSection(_ recording: Recording) -> some View {
        let transcript = recording.hasSpeechTranscript ? recording.transcription : nil
        return Section {
            if let transcription = transcript {
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
            } else if DeliveryStage(recording) == .transcribing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Transcribing…")
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
                if let transcription = transcript {
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

    private func transcriptPlaceholder(for recording: Recording) -> String {
        switch DeliveryStage(recording) {
        case .waitingToSend: return "Waiting to send"
        case .noSpeech: return "No speech detected"
        default: return "No transcript yet."
        }
    }

    // MARK: - Audio

    private static let shareNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()

    /// "Ramble 2026-11-06 0912.m4a"
    private static func shareFileName(for recording: Recording) -> String {
        let ext = recording.audioFileURL.pathExtension.isEmpty ? "m4a" : recording.audioFileURL.pathExtension
        return "Ramble \(shareNameFormatter.string(from: recording.createdAt)).\(ext)"
    }

    /// Shares the original recording, untouched, under a readable name.
    /// Falls back to the stored file if the copy can't be made.
    private static func shareableCopy(of url: URL, named name: String) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedAudio", isDirectory: true)
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true)
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return url
        }
    }

    @ViewBuilder
    private func audioSection(_ recording: Recording) -> some View {
        Section {
            #if DEBUG
            if MockDataProvider.enabled {
                MockAudioPlayerView(recording: recording)
            } else {
                audioContent(recording)
            }
            #else
            audioContent(recording)
            #endif
        } header: {
            HStack {
                Text("Audio")
                Spacer()
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityLabel("Share audio")
                }
            }
        }
    }

    @ViewBuilder
    private func audioContent(_ recording: Recording) -> some View {
        if recording.hasAudio {
            AudioPlayerView(audioURL: recording.audioFileURL)
        } else if recording.isAudioOnWatch {
            Button {
                HapticService.buttonTap()
                askWatchForAudio(recording)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch")
                        .foregroundStyle(Color.brandAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio on watch")
                            .foregroundStyle(Color.primary)
                        switch audioRequest {
                        case .asking:
                            Text("Asking your watch…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .openWatch:
                            Text("Open Ramble on your watch to sync.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .idle:
                            EmptyView()
                        }
                    }
                    Spacer()
                    if audioRequest == .asking {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Label("Audio file not available", systemImage: "waveform.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// True when the request went out.
    @discardableResult
    private func askWatchForAudio(_ recording: Recording) -> Bool {
        if PhoneConnectivityService.shared.requestAudio(for: recording.id) {
            audioRequest = .asking
            return true
        }
        audioRequest = .openWatch
        return false
    }

    // MARK: - Delivery

    private enum DeliveryAction {
        case retryTranscription, resendWebhook, unlock

        var title: String {
            switch self {
            case .retryTranscription, .resendWebhook: return "Retry"
            case .unlock: return "Unlock"
            }
        }
    }

    private struct DeliveryLine {
        var title: String
        var detail: String?
        var action: DeliveryAction?
    }

    private func deliveryLine(for recording: Recording) -> DeliveryLine {
        let stage = DeliveryStage(recording)
        switch stage {
        case .waitingToSend:
            let retryNote = "Ramble will try again on its own."
            if let error = recording.lastError, !error.isEmpty {
                return DeliveryLine(title: "Waiting to send", detail: "\(error) \(retryNote)")
            }
            return DeliveryLine(title: "Waiting to send", detail: retryNote)
        case .waitingOnWatch:
            return DeliveryLine(title: "Waiting on your watch")
        case .transcribing:
            return DeliveryLine(title: "Transcribing…", detail: "It goes out as soon as the transcript is ready.")
        case .heldForUnlock:
            return DeliveryLine(
                title: "Unlock to send",
                detail: "This note is saved. It sends as soon as you unlock Ramble.",
                action: .unlock
            )
        case .tooLong, .couldntSend:
            return DeliveryLine(title: stage.label)
        case .couldntTranscribe:
            let reason = recording.failureResult == "retries_exhausted"
                ? "Ramble couldn't reach a transcription service in time."
                : "Ramble couldn't turn this audio into text."
            if recording.retriesLeft == 0 {
                return DeliveryLine(title: "Couldn't transcribe", detail: "\(reason) Ramble tried once more.")
            }
            return DeliveryLine(title: "Couldn't transcribe", detail: reason, action: .retryTranscription)
        case .noSpeech:
            return DeliveryLine(title: "Nothing to send · no speech detected")
        case .agentHasIt:
            let first = recording.agentDelivery?.firstPickedUpAt
            return DeliveryLine(
                title: stage.label(for: recording),
                detail: first.map { "Picked up \(DateFormatters.timeFormatter.string(from: $0))" }
            )
        case .waitingForAgent:
            return DeliveryLine(title: stage.label(for: recording))
        case .didntSend:
            return DeliveryLine(title: "Didn't send", detail: lastWebhookFailure(recording), action: .resendWebhook)
        case .noAgent, .webhookSending, .checkingDelivery, .notPickedUp, .deliveredToWebhook:
            return DeliveryLine(title: stage.label)
        }
    }

    /// "Webhook failed after 3 attempts — HTTP 500", from the log.
    private func lastWebhookFailure(_ recording: Recording) -> String? {
        recording.activityLog.last { $0.message.hasPrefix("Webhook failed") }?.message
    }

    private func deliverySection(_ recording: Recording) -> some View {
        let line = deliveryLine(for: recording)
        let stage = DeliveryStage(recording)
        // Done reads as done: the same green check as the list row.
        let isDone = stage == .agentHasIt || stage == .deliveredToWebhook
        return Section {
            HStack(spacing: 12) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(.body.weight(.medium))
                    if let detail = line.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let action = line.action {
                    Button {
                        perform(action, for: recording)
                    } label: {
                        Text(action.title)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.brandAmber)
                    .controlSize(.small)
                }
            }
            if let copies = recording.agentDelivery?.agents, copies.count > 1 {
                ForEach(copies, id: \.connectionId) { copy in
                    AgentCopyRow(copy: copy)
                }
            }
            if line.action == .retryTranscription, audioRequest == .openWatch, !recording.hasAudio {
                Text("Open Ramble on your watch to sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func perform(_ action: DeliveryAction, for recording: Recording) {
        HapticService.buttonTap()
        switch action {
        case .retryTranscription:
            retryTranscription(recording)
        case .resendWebhook:
            WebhookQueueService.shared.resend(recordingId: recording.id)
        case .unlock:
            showUnlock = true
        }
    }

    /// Re-uploads from this iPhone as a retry. A watch note whose audio is
    /// only on the watch fetches it first.
    private func retryTranscription(_ recording: Recording) {
        guard recording.canRetryTranscription else { return }
        if !recording.hasAudio {
            guard askWatchForAudio(recording) else { return }
        }
        UploadQueueService.shared.retry(recordingId: recording.id)
        refreshRecording()
    }

    // MARK: - More menu

    private func moreMenu(_ recording: Recording) -> some View {
        Menu {
            if recording.canRetryTranscription {
                Button {
                    HapticService.buttonTap()
                    retryTranscription(recording)
                } label: {
                    Label("Retry Transcription", systemImage: "arrow.clockwise")
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

    /// Each logged step, always shown, in compact rows.
    private func activitySection(_ recording: Recording) -> some View {
        Section("Details") {
            Group {
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
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .environment(\.defaultMinListRowHeight, 26)
    }

    // MARK: - Helpers

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

/// One agent's pickup, listed under the delivery line when a note went to
/// several agents: "Muse · Has it 9:15", "Grok Bot · Waiting".
private struct AgentCopyRow: View {
    let copy: AgentCopy

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(copy.name ?? "Agent")
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        switch copy.state {
        case .pickedUp:
            return copy.pickedUpAt.map { "Has it · \(DateFormatters.timeFormatter.string(from: $0))" } ?? "Has it"
        case .waiting: return "Waiting"
        case .removed: return "Not picked up"
        }
    }

    private var dot: Color {
        switch copy.state {
        case .pickedUp: return .green
        case .waiting: return Color(.tertiaryLabel)
        case .removed: return .brandAmber
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: Recording(
            duration: 125,
            status: .completed,
            transcription: "This is a sample transcription that shows what the text might look like after recording.",
            activityLog: [
                ActivityEntry("Transcript received", httpStatus: 200),
                ActivityEntry("Webhook delivered", httpStatus: 200),
            ]
        ))
    }
}
