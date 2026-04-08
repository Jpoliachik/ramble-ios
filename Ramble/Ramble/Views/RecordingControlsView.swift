//
//  RecordingControlsView.swift
//  Ramble

import SwiftUI

struct RecordingControlsView: View {
    let isRecording: Bool
    let duration: TimeInterval
    var inputSourceName: String? = nil
    var audioLevel: Float = 0
    let onToggleRecording: () -> Void
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            if isRecording {
                Text(DateFormatters.formatDuration(duration))
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ZStack {
                RecordButtonView(isRecording: isRecording, audioLevel: audioLevel, action: onToggleRecording)

                if isRecording {
                    HStack {
                        Button {
                            onCancel?()
                        } label: {
                            Text("Cancel")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)

                        Spacer()
                    }
                    .padding(.leading, 20)
                }
            }

            if isRecording, let source = inputSourceName {
                Text("via \(source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: isRecording)
    }
}

#Preview {
    VStack {
        Spacer()
        RecordingControlsView(
            isRecording: false,
            duration: 0,
            onToggleRecording: {}
        )
        Spacer()
        RecordingControlsView(
            isRecording: true,
            duration: 65,
            inputSourceName: "iPhone",
            audioLevel: 0.5,
            onToggleRecording: {},
            onCancel: {}
        )
    }
}
