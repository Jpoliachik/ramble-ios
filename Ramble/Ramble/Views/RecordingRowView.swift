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

                // Content area
                switch recording.status {
                case .transcribing, .recorded:
                    transcribingPlaceholder
                case .completed, .failed:
                    if let preview = transcriptionPreview {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            // Status icon
            statusIcon
        }
        .padding(.vertical, 6)
    }

    private var transcriptionPreview: String? {
        guard let transcription = recording.transcription else { return nil }
        let collapsed = transcription
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private var transcribingPlaceholder: some View {
        HStack(spacing: 6) {
            // No icon here: the trailing badge already shows progress.
            Text(recording.status == .transcribing ? "Transcribing..." : "Waiting...")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch recording.status {
        case .completed:
            switch recording.webhookStatus {
            case .pending, .sending:
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            case .delivered, .none:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        case .failed:
            Image(systemName: recording.isModelNotInstalled ? "arrow.down.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(recording.isModelNotInstalled ? .orange : .red)
                .font(.subheadline)
        case .transcribing:
            // Same slot and size as the completed checkmark, so the row doesn't
            // shift as a recording moves through the queue.
            ProgressView()
                .controlSize(.mini)
        case .recorded:
            EmptyView()
        }
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
