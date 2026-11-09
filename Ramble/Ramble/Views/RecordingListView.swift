//
//  RecordingListView.swift
//  Ramble

import SwiftUI

struct RecordingListView: View {
    let recordingsByDay: [(date: Date, recordings: [Recording])]
    let onDelete: (Recording) -> Void
    let isRecording: Bool
    @Binding var scrollOffset: CGFloat

    @State private var deleteTarget: Recording?
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
                                    deleteTarget = recording
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
            .readableListWidth()
            .confirmationDialog(
                "Delete this recording?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { recording in
                Button("Delete Recording", role: .destructive) {
                    onDelete(recording)
                }
            } message: { _ in
                Text("This will permanently delete the recording and its transcript.")
            }
            .refreshable {
                await BackgroundTaskService.shared.refresh()
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                scrollOffset = newValue
            }
        }
    }

    private var emptyStateView: some View {
        ZStack {
            TrySayingView()
                .opacity(isRecording ? 0 : 1)
                .allowsHitTesting(!isRecording)

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

/// Home with no notes yet: a watch with a slow idle pulse and one idea at a
/// time of what to say. Each one leans on the agent's access to email,
/// calendar, and notes, so it reads as more than a Siri command.
private struct TrySayingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ideas = [
        "\u{201C}Tell Sarah Thursday works.\u{201D}",
        "\u{201C}Find a time with Dan next week.\u{201D}",
        "\u{201C}Add this to my project notes.\u{201D}",
        "\u{201C}Catch me up on the Acme thread.\u{201D}",
        "\u{201C}Send the team last week\u{2019}s numbers.\u{201D}",
    ]
    private static let interval: TimeInterval = 3.5

    var body: some View {
        VStack(spacing: 24) {
            // No watch to point at on iPad: just the ideas, above the mic button.
            if !ThisDevice.isPad {
                OnboardingWatchFrame {
                    OnboardingRecordGlyph()
                        .phaseAnimator([false, true]) { glyph, inhale in
                            glyph.scaleEffect(reduceMotion ? 1 : (inhale ? 1.06 : 0.96))
                        } animation: { _ in .easeInOut(duration: 1.4) }
                }
                .scaleEffect(1.2)
                .padding(.vertical, 18)
                .accessibilityHidden(true)
            }

            TimelineView(.periodic(from: .now, by: Self.interval)) { context in
                let index = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / Self.interval) % Self.ideas.count
                VStack(spacing: 14) {
                    Text("TRY SAYING")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)

                    Text(Self.ideas[index])
                        .font(.system(size: 24, design: .serif).italic())
                        .foregroundStyle(Color.obInk)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 64)
                        .id(index)
                        .transition(.opacity)

                    HStack(spacing: 7) {
                        ForEach(Self.ideas.indices, id: \.self) { i in
                            Circle()
                                .fill(i == index ? Color.brandAmber : Color.obInk.opacity(0.12))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .animation(.easeInOut(duration: 0.4), value: index)
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
