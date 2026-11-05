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
                    if let note = deliveryNote {
                        Text(note)
                            .font(.caption)
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

    private var stage: DeliveryStage { DeliveryStage(recording) }

    /// Second line for notes that are stuck, so a transcript with
    /// nowhere to go never reads as done. Same words as the note screen.
    private var deliveryNote: String? {
        switch stage {
        case .onPhone, .didntSend, .couldntTranscribe: return stage.label
        default: return nil
        }
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
            ProgressView()
                .controlSize(.mini)
            Text(stage.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if stage.isInProgress {
            // The transcribing placeholder already shows a spinner.
            if recording.status == .completed {
                ProgressView()
                    .controlSize(.mini)
            }
        } else if let symbol = stage.systemImage {
            Image(systemName: symbol)
                .foregroundStyle(stage.iconTint)
                .font(.subheadline)
                .accessibilityLabel(stage.label)
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
