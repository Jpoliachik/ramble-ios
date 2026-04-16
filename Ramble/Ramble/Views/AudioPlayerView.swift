//
//  AudioPlayerView.swift
//  Ramble
//

import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let audioURL: URL

    @StateObject private var player = AudioPlayerService()
    @State private var peaks: [Float] = Self.placeholderPeaks
    @State private var isSeeking = false
    @State private var seekProgress: Double = 0

    private var displayProgress: Double {
        isSeeking ? seekProgress : player.progress
    }

    var body: some View {
        VStack(spacing: 12) {
            waveform
            controls
        }
        .task {
            let extracted = await Self.extractPeaks(from: audioURL)
            withAnimation(.easeInOut(duration: 0.3)) {
                peaks = extracted
            }
            player.load(url: audioURL)
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Waveform

    private var waveform: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawWaveform(context: context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(seekGesture(width: geometry.size.width))
        }
        .frame(height: 48)
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let barCount = peaks.count
        guard barCount > 0 else { return }

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

            let barFraction = Double(index) / Double(barCount)
            let color: Color = barFraction < displayProgress
                ? .accentColor
                : .secondary.opacity(0.25)

            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(color)
            )
        }
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isSeeking = true
                seekProgress = max(0, min(1, value.location.x / width))
            }
            .onEnded { value in
                let fraction = max(0, min(1, value.location.x / width))
                player.seek(to: fraction)
                isSeeking = false
            }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Text(DateFormatters.formatDuration(player.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Spacer()

            Button {
                HapticService.buttonTap()
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("-\(DateFormatters.formatDuration(max(0, player.duration - player.currentTime)))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: - Placeholder

    private static let placeholderPeaks: [Float] = Array(repeating: 0.3, count: 70)

    // MARK: - Waveform Extraction

    static func extractPeaks(from url: URL, sampleCount: Int = 70) async -> [Float] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let audioFile = try? AVAudioFile(forReading: url) else {
                    continuation.resume(returning: [])
                    return
                }

                let frameCount = AVAudioFrameCount(audioFile.length)
                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(
                          pcmFormat: audioFile.processingFormat,
                          frameCapacity: frameCount
                      )
                else {
                    continuation.resume(returning: [])
                    return
                }

                do {
                    try audioFile.read(into: buffer)
                } catch {
                    continuation.resume(returning: [])
                    return
                }

                guard let channelData = buffer.floatChannelData?[0] else {
                    continuation.resume(returning: [])
                    return
                }

                let totalFrames = Int(buffer.frameLength)
                let samplesPerBar = max(1, totalFrames / sampleCount)
                let actualCount = min(sampleCount, totalFrames)
                var peaks = [Float]()
                peaks.reserveCapacity(actualCount)

                for i in 0..<actualCount {
                    let start = i * samplesPerBar
                    let end = min(start + samplesPerBar, totalFrames)
                    var peak: Float = 0
                    for j in start..<end {
                        peak = max(peak, abs(channelData[j]))
                    }
                    peaks.append(peak)
                }

                // Normalize to 0...1
                let maxPeak = peaks.max() ?? 1
                if maxPeak > 0 {
                    peaks = peaks.map { $0 / maxPeak }
                }

                continuation.resume(returning: peaks)
            }
        }
    }
}
