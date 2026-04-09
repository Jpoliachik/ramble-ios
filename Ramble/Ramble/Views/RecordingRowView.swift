//
//  RecordingRowView.swift
//  Ramble

import SwiftUI

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                // Top line: duration + time
                HStack(alignment: .firstTextBaseline) {
                    Text(DateFormatters.formatDuration(recording.duration))
                        .font(.system(.headline, design: .rounded, weight: .semibold))

                    Text(DateFormatters.timeFormatter.string(from: recording.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Status-aware content area
                switch recording.status {
                case .transcribing, .recorded:
                    transcribingPlaceholder
                case .completed:
                    if let transcription = recording.transcription, !transcription.isEmpty {
                        Text(transcription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                case .failed:
                    if let transcription = recording.transcription, !transcription.isEmpty {
                        Text(transcription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    failedLabel
                }
            }

            Spacer(minLength: 4)

            // Status icon — only for completed (checkmark)
            if recording.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }

    private var transcribingPlaceholder: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text(recording.status == .transcribing ? "Transcribing..." : "Waiting...")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var failedLabel: some View {
        Image(systemName: recording.isModelNotInstalled ? "arrow.down.circle.fill" : "exclamationmark.circle.fill")
            .foregroundStyle(recording.isModelNotInstalled ? .orange : .red)
            .font(.caption)
    }
}

#Preview {
    List {
        RecordingRowView(recording: Recording(
            duration: 125,
            status: .completed,
            transcription: "This is a sample transcription that shows what the text might look like."
        ))
        RecordingRowView(recording: Recording(
            duration: 45,
            status: .transcribing
        ))
        RecordingRowView(recording: Recording(
            duration: 200,
            status: .recorded
        ))
        RecordingRowView(recording: Recording(
            duration: 30,
            status: .failed,
            lastError: "Network error"
        ))
    }
}
