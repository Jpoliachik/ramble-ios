//
//  MockAudioPlayerView.swift
//  Ramble
//
//  Static waveform + controls for App Store screenshots. Not shipped in release builds.
//

#if DEBUG

import SwiftUI

struct MockAudioPlayerView: View {
    let recording: Recording

    var body: some View {
        VStack(spacing: 12) {
            waveform
            controls
        }
    }

    private var waveform: some View {
        Canvas { context, size in
            let peaks = Self.mockPeaks(seed: seed)
            let barCount = peaks.count
            let spacing: CGFloat = 2
            let barWidth = max(1, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let midY = size.height / 2

            for (index, peak) in peaks.enumerated() {
                let x = CGFloat(index) * (barWidth + spacing)
                let barHeight = max(barWidth, CGFloat(peak) * size.height * 0.9)
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.secondary.opacity(0.25))
                )
            }
        }
        .frame(height: 48)
    }

    private var controls: some View {
        HStack {
            Text(DateFormatters.formatDuration(0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Spacer()

            Image(systemName: "play.fill")
                .font(.title3)

            Spacer()

            Text("-\(DateFormatters.formatDuration(recording.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var seed: UInt64 {
        var hash: UInt64 = 5381
        for byte in recording.id.uuidString.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }

    static func mockPeaks(seed: UInt64, count: Int = 70) -> [Float] {
        var rng = SeededRNG(state: seed == 0 ? 1 : seed)
        return (0..<count).map { i in
            let progress = Float(i) / Float(max(1, count - 1))
            let envelope = sin(progress * .pi) * 0.5 + 0.5
            let noise = Float.random(in: 0.2...1.0, using: &rng)
            return min(1.0, max(0.08, envelope * 0.55 + noise * 0.45))
        }
    }
}

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

#endif
