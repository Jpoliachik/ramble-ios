//
//  RecordingListView.swift
//  Ramble

import SwiftUI

struct RecordingListView: View {
    let recordingsByDay: [(date: Date, recordings: [Recording])]
    let onDelete: (Recording) -> Void
    @Binding var scrollOffset: CGFloat

    var body: some View {
        if recordingsByDay.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(recordingsByDay, id: \.date) { day in
                    Section {
                        ForEach(day.recordings) { recording in
                            NavigationLink(value: recording) {
                                RecordingRowView(recording: recording)
                            }
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
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                scrollOffset = newValue
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Hit record and ramble",
            systemImage: "waveform",
            description: Text("Talk first, organize later.")
        )
    }
}

#Preview {
    RecordingListView(
        recordingsByDay: [
            (
                date: Date(),
                recordings: [
                    Recording(duration: 125, status: .completed, transcription: "Test"),
                    Recording(duration: 45, status: .transcribing)
                ]
            )
        ],
        onDelete: { _ in },
        scrollOffset: .constant(0)
    )
}
