//
//  RecordButtonView.swift
//  Ramble
//

import SwiftUI

struct RecordButtonView: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize: CGFloat = 72
    private let innerSize: CGFloat = 64

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                // Inner shape (circle when idle, rounded square when recording)
                RoundedRectangle(cornerRadius: isRecording ? 8 : innerSize / 2)
                    .fill(Color.red)
                    .frame(
                        width: isRecording ? 28 : innerSize,
                        height: isRecording ? 28 : innerSize
                    )
                    .scaleEffect(isRecording ? pulseScale : 1.0)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startPulseAnimation()
            } else {
                pulseScale = 1.0
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        RecordButtonView(isRecording: false) {}
        RecordButtonView(isRecording: true) {}
    }
}
