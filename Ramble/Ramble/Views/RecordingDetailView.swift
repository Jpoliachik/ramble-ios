//
//  RecordingDetailView.swift
//  Ramble
//

import SwiftUI

struct RecordingDetailView: View {
    let recording: Recording
    @State private var showCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Metadata section
                metadataSection

                Divider()

                // Transcript section
                transcriptSection
            }
            .padding()
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
    }

    private var metadataSection: some View {
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

                statusBadge
            }
        }
    }

    private var statusBadge: some View {
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

    private var transcriptSection: some View {
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
                Text(transcriptPlaceholder)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    private var transcriptPlaceholder: String {
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
            transcription: "This is a sample transcription that shows what the full text might look like. It could be quite long with multiple sentences describing various topics discussed during the recording session.",
            transcriptionStatus: .completed
        ))
    }
}
