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

    private var glowScale: CGFloat {
        guard isRecording else { return 1.0 }
        return 1.0 + CGFloat(audioLevel) * 0.4
    }

    private var glowOpacity: Double {
        guard isRecording else { return 0 }
        return Double(audioLevel) * 0.5
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Audio level glow
                Circle()
                    .fill(Color.red)
                    .frame(width: buttonSize, height: buttonSize)
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)
                    .blur(radius: 8)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)

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
        RecordButtonView(isRecording: true) {}
    }
}
