//
//  RambleBarsMark.swift
//  Ramble
//

import SwiftUI

/// The three-bar half of the Ramble mark — rounded vertical bars that ride
/// a single sine wave. Each bar shares the same frequency with a small phase
/// offset, so the motion reads as a wave traveling across the mark rather
/// than three independent meters.
///
/// Used as the empty-state mark on `MainView` and as a subtle decorative
/// element on the onboarding Welcome screen. Pass a faded `tint` for ambient
/// usage where the mark should blend toward the background.
struct RambleBarsMark: View {
    let size: CGFloat
    var tint: Color = .obInkSoft
    /// Delay before the entrance grow animation starts. Useful when the parent
    /// wants to stagger this mark behind other elements.
    var appearDelay: Double = 0

    @State private var appearScale: CGFloat = 0

    private static let baseHeights: [CGFloat] = [0.55, 0.85, 0.45]
    private static let phaseOffsets: [Double] = [0, 0.55, 1.1]
    private static let amplitude: CGFloat = 0.12
    private static let speed: Double = 1.8

    var body: some View {
        let barWidth = size * 0.18
        let spacing = size * 0.05

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<3, id: \.self) { i in
                    let osc = sin(t * Self.speed + Self.phaseOffsets[i])
                    let height = size * (Self.baseHeights[i] + Self.amplitude * CGFloat(osc))
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: size, height: size)
        }
        .scaleEffect(x: 1, y: appearScale, anchor: .center)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(appearDelay)) {
                appearScale = 1
            }
        }
    }
}
