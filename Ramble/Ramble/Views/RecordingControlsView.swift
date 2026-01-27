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

    var body: some View {
        VStack(spacing: 16) {
            // Duration timer
            Text(DateFormatters.formatDuration(duration))
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(isRecording ? .red : .secondary)
                .opacity(isRecording || duration > 0 ? 1 : 0.3)

            RecordButtonView(isRecording: isRecording, audioLevel: audioLevel, action: onToggleRecording)

            if isRecording, let source = inputSourceName {
                Text("via \(source)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 24)
    }
}

#Preview {
    VStack {
        RecordingControlsView(
            isRecording: false,
            duration: 0,
            onToggleRecording: {}
        )
        RecordingControlsView(
            isRecording: true,
            duration: 65,
            onToggleRecording: {}
        )
    }
}
