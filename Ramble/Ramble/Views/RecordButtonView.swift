//
//  RecordButtonView.swift
//  Ramble
//

import SwiftUI

struct RecordButtonView: View {
    let isRecording: Bool
    var audioLevel: Float = 0
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize: CGFloat = 72
    private let innerSize: CGFloat = 64

    /// Maps audio level (0...1) to a fill color from dark red to bright red
    private var innerFillColor: Color {
        guard isRecording else { return .red }
        let brightness = 0.4 + Double(audioLevel) * 0.6
        return Color(red: brightness, green: 0.05 * brightness, blue: 0.05 * brightness)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                // Inner shape (circle when idle, rounded square when recording)
                // Background fill responds to audio level
                RoundedRectangle(cornerRadius: isRecording ? 8 : innerSize / 2)
                    .fill(innerFillColor)
                    .frame(
                        width: isRecording ? 28 : innerSize,
                        height: isRecording ? 28 : innerSize
                    )
                    .scaleEffect(isRecording ? pulseScale : 1.0)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.08), value: isRecording)
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
            .easeInOut(duration: 0.5)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        RecordButtonView(isRecording: false) {}
        RecordButtonView(isRecording: true, audioLevel: 0.0) {}
        RecordButtonView(isRecording: true, audioLevel: 0.5) {}
        RecordButtonView(isRecording: true, audioLevel: 1.0) {}
    }
}
