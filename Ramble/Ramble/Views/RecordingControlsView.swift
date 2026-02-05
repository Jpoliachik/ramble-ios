//
//  RecordingControlsView.swift
//  Ramble
//

import SwiftUI

struct RecordingControlsView: View {
    let isRecording: Bool
    let duration: TimeInterval
    var inputSourceName: String? = nil
    var audioLevel: Float = 0
    let onToggleRecording: () -> Void
    var onSelectInput: ((AudioInput) -> Void)? = nil

    @ObservedObject private var audioInputService = AudioInputService.shared

    var body: some View {
        VStack(spacing: 16) {
            // Duration timer
            Text(DateFormatters.formatDuration(duration))
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(isRecording ? .red : .secondary)
                .opacity(isRecording || duration > 0 ? 1 : 0.3)

            RecordButtonView(isRecording: isRecording, audioLevel: audioLevel, action: onToggleRecording)

            // Audio input picker - always visible for easy selection
            AudioInputPickerView(
                inputService: audioInputService,
                isRecording: isRecording,
                onSelect: { input in
                    onSelectInput?(input)
                }
            )
        }
        .padding(.vertical, 24)
        .onAppear {
            audioInputService.refreshAvailableInputs()
        }
    }
}

#Preview {
    VStack {
        RecordingControlsView(
            isRecording: false,
            duration: 0,
            onToggleRecording: {},
            onSelectInput: { _ in }
        )
        RecordingControlsView(
            isRecording: true,
            duration: 65,
            onToggleRecording: {},
            onSelectInput: { _ in }
        )
    }
}
