//
//  RecordingLiveActivity.swift
//  RambleWidgets
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RambleActivityAttributes.self) { context in
            // Lock screen and Notification Center.
            HStack(spacing: 12) {
                RambleDiscardButton(size: 30)

                Spacer(minLength: 6)

                Text("Recording")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                elapsed(from: context.state.startedAt, size: 24)
                    .frame(minWidth: 76, alignment: .leading)

                Spacer(minLength: 6)

                RambleStopButton(size: 42)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Everything goes in `.bottom`, which spans the island's full width.
                // `.leading` and `.trailing` are narrow regions meant to flank the
                // camera, so a button row in one and a label in the other leaves
                // both truncated ("Reco... 0:...").
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        RambleDiscardButton(size: 32)

                        Spacer(minLength: 6)

                        Text("Recording")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize()

                        elapsed(from: context.state.startedAt, size: 26)
                            .frame(minWidth: 76, alignment: .leading)

                        Spacer(minLength: 6)

                        RambleStopButton(size: 46)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                elapsed(from: context.state.startedAt, size: 15)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    /// The activity runs its own timer, so the app never pushes a per-second update
    /// just to keep the elapsed time honest.
    ///
    /// `Text(timerInterval:)` rather than `Text(_:style:.timer)`: the island reserves
    /// width for it, so it can't be dropped when the digits roll over. Compact
    /// regions silently drop content that doesn't fit, which is how the compact
    /// island ended up showing only the microphone.
    private func elapsed(from startedAt: Date, size: CGFloat) -> some View {
        Text(timerInterval: startedAt...startedAt.addingTimeInterval(8 * 3600), countsDown: false)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.red)
            .lineLimit(1)
    }
}

/// Discard, small and quiet on the leading edge. Runs a `LiveActivityIntent`, so
/// it performs in the app and acts on the real recorder.
struct RambleDiscardButton: View {
    var size: CGFloat = 30

    var body: some View {
        Button(intent: CancelRambleIntent()) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discard recording")
    }
}

/// Stop, the primary action, so it sits on the trailing edge and is the largest
/// target in the row. Reads as the record button's other half: a red square
/// inside a white ring, the shape Voice Memos uses.
struct RambleStopButton: View {
    var size: CGFloat = 44

    var body: some View {
        Button(intent: StopRambleIntent()) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: size * 0.14)
                    .fill(Color.red)
                    .frame(width: size * 0.44, height: size * 0.44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
    }
}
