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

                // Transcription preview
                if let transcription = recording.transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                } else if recording.transcriptionStatus == .pending {
                    Text("Tap to transcribe")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusView: some View {
        switch recording.transcriptionStatus {
        case .pending:
            EmptyView()
        case .uploading, .processing:
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
            transcription: "This is a sample transcription that shows what the text might look like.",
            transcriptionStatus: .completed
        ))
        RecordingRowView(recording: Recording(
            duration: 45,
            transcriptionStatus: .processing
        ))
        RecordingRowView(recording: Recording(
            duration: 200,
            transcriptionStatus: .pending
        ))
    }
}
