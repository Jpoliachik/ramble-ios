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

    private var durationWarning: String? {
        guard isRecording, duration >= Constants.Recording.longWarningDuration else { return nil }
        return "Long recording"
    }

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
                        .transition(.opacity)
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
                }
            }

            if isRecording {
                if let warning = durationWarning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                } else if let source = inputSourceName {
                    Text("via \(source)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
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
