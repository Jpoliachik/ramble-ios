//
//  RecordingListView.swift
//  Ramble
//

import SwiftUI

struct RecordingListView: View {
    let recordingsByDay: [(date: Date, recordings: [Recording])]
    let onDelete: (Recording) -> Void

    var body: some View {
        if recordingsByDay.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(recordingsByDay, id: \.date) { day in
                    Section {
                        ForEach(day.recordings) { recording in
                            RecordingRowView(recording: recording)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        onDelete(recording)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(DateFormatters.formatDayHeader(for: day.date))
                            .font(.headline)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No recordings yet")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Tap the record button to start")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
    }
}

#Preview {
    RecordingListView(
        recordingsByDay: [
            (
                date: Date(),
                recordings: [
                    Recording(duration: 125, transcription: "Test", transcriptionStatus: .completed),
                    Recording(duration: 45, transcriptionStatus: .processing)
                ]
            )
        ],
        onDelete: { _ in }
    )
}
