//
//  RecordingRowView.swift
//  Ramble
//

import SwiftUI

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            Text(DateFormatters.timeFormatter.string(from: recording.createdAt))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                // Duration and status row
                HStack {
                    Text(DateFormatters.formatDuration(recording.duration))
                        .font(.headline)

                    Spacer()

                    statusView
                }

                // Transcription preview (1 line only)
                if let transcription = recording.transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusView: some View {
        switch recording.status {
        case .recorded:
            EmptyView()
        case .transcribing:
            ProgressView()
                .scaleEffect(0.8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
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
    }
}
