//
//  RambleBarsMark.swift
//  Ramble
//

import SwiftUI

/// The Ramble logo mark — a red circle on the left with three rounded bars
/// riding to its right; the closest bar tucks half-under the circle. Entrance
/// pops the circle in first, then cascades the bars outward; once settled,
/// pulses in a wave that travels from the circle through the bars.
///
/// Used as the empty-state mark on `RecordingListView` and as the welcome
/// hero on the onboarding Welcome screen. Mirrors `website/src/components/animated-logo.tsx`.
struct RambleBarsMark: View {
    let size: CGFloat
    /// Delay before the entrance pop-in starts. Set this when a parent fade
    /// hides the mark for a window — otherwise the pop happens off-screen.
    var appearDelay: Double = 0

    @State private var circleAppear: CGFloat = 0
    @State private var bar1Appear: CGFloat = 0
    @State private var bar2Appear: CGFloat = 0
    @State private var bar3Appear: CGFloat = 0

    private static let cycleDuration: Double = 2.8

    // Pulse keyframes (fraction-of-cycle timing + peak scale).
    // Sourced from the website logo so the two stay visually identical.
    private static let circlePulse = Pulse(rise: 0.00, peak: 0.10, fall: 0.22, peakScale: 1.12)
    private static let bar1Pulse   = Pulse(rise: 0.00, peak: 0.22, fall: 0.38, peakScale: 1.18)
    private static let bar2Pulse   = Pulse(rise: 0.00, peak: 0.34, fall: 0.50, peakScale: 1.22)
    private static let bar3Pulse   = Pulse(rise: 0.00, peak: 0.46, fall: 0.62, peakScale: 1.26)

    // Pop-in cascade. Circle anchors the entrance; bars follow in 80ms beats.
    private static let circlePopDelay: Double = 0.00
    private static let bar1PopDelay: Double   = 0.22
    private static let bar2PopDelay: Double   = 0.30
    private static let bar3PopDelay: Double   = 0.38
    private static let popResponse: Double    = 0.42
    private static let popDamping: Double     = 0.62

    var body: some View {
        // Proportions baked from the SVG (100×100 viewBox).
        // Circle: cx=36 cy=50 r=22 — its right edge sits at x=58.
        // Bar 1 centered on x=58 keeps the half-tuck under the circle. Bars
        // 2 and 3 use a 0.12 step (slightly tighter than the SVG's 0.13).
        let circleSize    = size * 0.44
        let circleCenterX = size * 0.36
        let centerY       = size * 0.50
        let barWidth      = size * 0.10
        let barCorner     = size * 0.05
        let bar1Height    = size * 0.32
        let bar2Height    = size * 0.48
        let bar3Height    = size * 0.32
        let bar1CenterX   = size * 0.58
        let bar2CenterX   = size * 0.70
        let bar3CenterX   = size * 0.82

        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let progress = (context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.cycleDuration)) / Self.cycleDuration

            ZStack {
                bar(width: barWidth, height: bar1Height, corner: barCorner)
                    .scaleEffect(x: 1, y: Self.bar1Pulse.scale(at: progress), anchor: .center)
                    .scaleEffect(bar1Appear, anchor: .center)
                    .position(x: bar1CenterX, y: centerY)

                bar(width: barWidth, height: bar2Height, corner: barCorner)
                    .scaleEffect(x: 1, y: Self.bar2Pulse.scale(at: progress), anchor: .center)
                    .scaleEffect(bar2Appear, anchor: .center)
                    .position(x: bar2CenterX, y: centerY)

                bar(width: barWidth, height: bar3Height, corner: barCorner)
                    .scaleEffect(x: 1, y: Self.bar3Pulse.scale(at: progress), anchor: .center)
                    .scaleEffect(bar3Appear, anchor: .center)
                    .position(x: bar3CenterX, y: centerY)

                Circle()
                    .fill(Color.brandRed)
                    .frame(width: circleSize, height: circleSize)
                    .scaleEffect(Self.circlePulse.scale(at: progress), anchor: .center)
                    .scaleEffect(circleAppear, anchor: .center)
                    .position(x: circleCenterX, y: centerY)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(popSpring().delay(appearDelay + Self.circlePopDelay)) {
                circleAppear = 1
            }
            withAnimation(popSpring().delay(appearDelay + Self.bar1PopDelay)) {
                bar1Appear = 1
            }
            withAnimation(popSpring().delay(appearDelay + Self.bar2PopDelay)) {
                bar2Appear = 1
            }
            withAnimation(popSpring().delay(appearDelay + Self.bar3PopDelay)) {
                bar3Appear = 1
            }
        }
    }

    private func bar(width: CGFloat, height: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.obInk)
            .frame(width: width, height: height)
    }

    private func popSpring() -> Animation {
        .spring(response: Self.popResponse, dampingFraction: Self.popDamping)
    }
}

private struct Pulse {
    let rise: Double
    let peak: Double
    let fall: Double
    let peakScale: CGFloat

    func scale(at progress: Double) -> CGFloat {
        if progress < rise || progress > fall { return 1 }
        if progress <= peak {
            let t = (progress - rise) / (peak - rise)
            return 1 + (peakScale - 1) * easeInOut(t)
        }
        let t = (progress - peak) / (fall - peak)
        return peakScale - (peakScale - 1) * easeInOut(t)
    }

    private func easeInOut(_ t: Double) -> CGFloat {
        let c = max(0, min(1, t))
        return CGFloat(c < 0.5 ? 2 * c * c : 1 - pow(-2 * c + 2, 2) / 2)
    }
}
