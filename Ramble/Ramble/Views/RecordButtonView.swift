//
//  RecordButtonView.swift
//  Ramble

import SwiftUI

struct RecordButtonView: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize: CGFloat = 76
    private let innerSize: CGFloat = 66

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring — always visible
                Circle()
                    .stroke(Color.brandRed.opacity(0.8), lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                // Inner shape — filled circle when idle, rounded square when recording
                RoundedRectangle(cornerRadius: isRecording ? 8 : innerSize / 2)
                    .fill(Color.brandRed)
                    .frame(
                        width: isRecording ? 24 : innerSize,
                        height: isRecording ? 24 : innerSize
                    )
                    .scaleEffect(isRecording ? pulseScale : 1.0)
            }
            .frame(width: buttonSize + 8, height: buttonSize + 8)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
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
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
    }
}

// MARK: - Audio Waveform

struct AudioWaveformView: View {
    let audioLevel: Float

    private let barCount = 8
    private let barWidth: CGFloat = 5.5
    private let barSpacing: CGFloat = 4.5
    private let propagationDelay: Double = 0.04
    private let sensitivity: Float = 0.7

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                WaveformBar(
                    audioLevel: min(audioLevel * sensitivity, 1.0),
                    delay: Double(i) * propagationDelay,
                    barWidth: barWidth
                )
            }
        }
    }
}

/// Individual waveform bar that responds to audio level with a configurable delay,
/// creating a left-to-right wave propagation effect.
private struct WaveformBar: View {
    let audioLevel: Float
    let delay: Double
    let barWidth: CGFloat

    @State private var displayLevel: Float = 0

    private let minHeight: CGFloat = 8
    private let maxHeight: CGFloat = 36

    private var barHeight: CGFloat {
        minHeight + (maxHeight - minHeight) * CGFloat(displayLevel)
    }

    var body: some View {
        Capsule()
            .fill(Color.brandRed)
            .frame(width: barWidth, height: barHeight)
            .onChange(of: audioLevel) { _, newLevel in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.65)) {
                        displayLevel = newLevel
                    }
                }
            }
    }
}

#Preview {
    VStack(spacing: 40) {
        RecordButtonView(isRecording: false) {}
        RecordButtonView(isRecording: true) {}

        HStack(spacing: 20) {
            AudioWaveformView(audioLevel: 0)
            AudioWaveformView(audioLevel: 0.5)
            AudioWaveformView(audioLevel: 1.0)
        }
    }
}
