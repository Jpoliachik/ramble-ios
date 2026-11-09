//
//  RecordingRowView.swift
//  Ramble
//
//  One note in the list: duration and time, the first line of the
//  transcript, a caption when the note needs words, and a trailing icon
//  (specs/phone.md "Row states").
//

import SwiftUI

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        let stage = DeliveryStage(recording)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(DateFormatters.formatDuration(recording.duration))
                        .font(.system(.headline, design: .rounded, weight: .semibold))

                    Text(DateFormatters.timeFormatter.string(from: recording.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let preview = transcriptionPreview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if stage == .transcribing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(stage.label)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else if let caption = caption(for: stage) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if stage == .webhookSending {
                ProgressView()
                    .controlSize(.mini)
            } else if let symbol = stage.systemImage {
                Image(systemName: symbol)
                    .foregroundStyle(stage.tint(for: recording))
                    .font(.subheadline)
                    .accessibilityLabel(stage.label(for: recording))
            }
        }
        .padding(.vertical, 6)
    }

    /// The stage's words, or "Audio on watch" for a transcribed watch note
    /// whose audio hasn't reached the phone when nothing else applies.
    private func caption(for stage: DeliveryStage) -> String? {
        if let caption = stage.caption { return caption }
        if recording.status == .completed && recording.isAudioOnWatch { return "Audio on watch" }
        return nil
    }

    private var transcriptionPreview: String? {
        guard let transcription = recording.transcription else { return nil }
        let collapsed = transcription
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

#Preview {
    List {
        RecordingRowView(recording: Recording(
            duration: 125,
            status: .completed,
            transcription: "This is a sample transcription that shows what the text might look like."
        ))
        RecordingRowView(recording: Recording(duration: 45, status: .transcribing))
        RecordingRowView(recording: Recording(duration: 200, status: .recorded))
        RecordingRowView(recording: Recording(duration: 30, status: .failed))
    }
}
