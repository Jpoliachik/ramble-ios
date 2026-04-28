//
//  RecordingListView.swift
//  Ramble

import SwiftUI

struct RecordingListView: View {
    let recordingsByDay: [(date: Date, recordings: [Recording])]
    let onDelete: (Recording) -> Void
    let isRecording: Bool
    @Binding var scrollOffset: CGFloat

    @State private var showLockHint = false
    @State private var lockHintTask: Task<Void, Never>?

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
        ZStack {
            VStack(spacing: 28) {
                RambleBarsMark(size: 72)

                (Text("Hit record and ") + Text("ramble").italic().foregroundColor(Color.brandRed))
                    .font(.system(size: 18, design: .serif).weight(.medium))
                    .tracking(-0.5)
                    .foregroundStyle(Color.obInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isRecording ? 0 : 1)

            Text("Pocket it — we'll keep listening")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.obInk.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(showLockHint ? 1 : 0)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: isRecording)
        .animation(.easeInOut(duration: 0.6), value: showLockHint)
        .onChange(of: isRecording) { _, newValue in
            lockHintTask?.cancel()
            if newValue {
                lockHintTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    showLockHint = true
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    showLockHint = false
                }
            } else {
                showLockHint = false
            }
        }
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
        isRecording: false,
        scrollOffset: .constant(0)
    )
}
