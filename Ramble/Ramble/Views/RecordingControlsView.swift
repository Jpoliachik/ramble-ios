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

    @State private var showCancelConfirmation = false

    /// From 55:00 the timer counts down to the 60:00 stop.
    private var isNearCap: Bool {
        isRecording && duration >= Constants.Recording.warningDuration
    }

    private var timerText: String {
        isNearCap
            ? DateFormatters.formatDuration(max(0, Constants.Recording.maxDuration - duration))
            : DateFormatters.formatDuration(duration)
    }

    var body: some View {
        VStack(spacing: 8) {
            if isRecording {
                Text(timerText)
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }

            if !isRecording {
                CompactMicButton(action: onToggleRecording)
                    .transition(.opacity)
            } else {
                ZStack {
                    RecordButtonView(isRecording: isRecording, action: onToggleRecording)

                    if isRecording {
                        HStack {
                            Button {
                                HapticService.buttonTap()
                                if duration > 30 {
                                    showCancelConfirmation = true
                                } else {
                                    onCancel?()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, height: 26)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                "Discard recording?",
                                isPresented: $showCancelConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Discard", role: .destructive) {
                                    onCancel?()
                                }
                            } message: {
                                Text("This will delete \(DateFormatters.formatDuration(duration)) of audio.")
                            }

                            Spacer()
                        }
                        .padding(.leading, 20)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                        AudioWaveformView(audioLevel: audioLevel)
                            .offset(x: 90)
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }

            if isRecording {
                if isNearCap {
                    Text("Stops at 60:00")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if let source = inputSourceName {
                    Text("via \(source)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: isRecording)
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
