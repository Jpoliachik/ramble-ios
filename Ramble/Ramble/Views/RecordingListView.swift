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
        VStack(spacing: 28) {
            RambleBarsMark()
                .frame(width: 72, height: 72)

            (Text("Hit record and ") + Text("ramble").italic().foregroundColor(Color.brandRed))
                .font(.system(size: 22, design: .serif).weight(.medium))
                .tracking(-0.5)
                .foregroundStyle(Color.obInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The three-bar half of the Ramble mark — rounded vertical bars that ride
/// a single sine wave. Each bar shares the same frequency with a small phase
/// offset, so the motion reads as a wave traveling across the mark rather
/// than three independent meters.
private struct RambleBarsMark: View {
    private static let baseHeights: [CGFloat] = [0.55, 0.85, 0.45]
    private static let phaseOffsets: [Double] = [0, 0.55, 1.1]
    private static let amplitude: CGFloat = 0.12
    private static let speed: Double = 1.8

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let unit = geo.size.height
                let barWidth = unit * 0.18
                let spacing = unit * 0.05

                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<3, id: \.self) { i in
                        let osc = sin(t * Self.speed + Self.phaseOffsets[i])
                        let height = unit * (Self.baseHeights[i] + Self.amplitude * CGFloat(osc))
                        Capsule(style: .continuous)
                            .fill(Color.obInkSoft)
                            .frame(width: barWidth, height: height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
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
