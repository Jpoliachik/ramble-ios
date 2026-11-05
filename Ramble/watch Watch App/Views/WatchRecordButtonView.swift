//
//  WatchRecordButtonView.swift
//  watch Watch App
//
//  The only control on the home screen. Amber ring with a fill at rest,
//  three level bars while recording, a check that draws itself after a
//  stop, and a breathing ring on first launch.
//

import SwiftUI

struct WatchRecordButtonView: View {
    /// Diameter of the ring. Home sizes it from the screen width.
    let size: CGFloat
    let isRecording: Bool
    var audioLevel: Float = 0
    /// True for about 0.8 s after a note is saved.
    var showCheck = false
    /// True on first launch until the first note exists.
    var breathe = false
    /// Mic off: the button still takes taps, but looks unavailable.
    var dimmed = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Proportions from the spec, drawn at 120pt on a 46mm watch
    private var unit: CGFloat { size / 120 }
    private var strokeWidth: CGFloat { 5 * unit }
    private var fillSize: CGFloat { 100 * unit }
    private var barWidth: CGFloat { 14 * unit }
    private var barSpacing: CGFloat { 8 * unit }
    private var minBarHeight: CGFloat { 14 * unit }
    private var maxBarHeight: CGFloat { 54 * unit }
    private let barScales: [CGFloat] = [0.7, 1.0, 0.8]

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        return minBarHeight + (maxBarHeight - minBarHeight) * level * barScales[index]
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.brandAmber, lineWidth: strokeWidth)
                    .frame(width: size, height: size)

                if isRecording {
                    HStack(spacing: barSpacing) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(Color.brandAmber)
                                .frame(width: barWidth, height: barHeight(for: index))
                        }
                    }
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: audioLevel)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Color.brandAmber)
                        .frame(width: fillSize, height: fillSize)
                        .overlay {
                            if showCheck {
                                DrawnCheck(lineWidth: 6 * unit)
                                    .frame(width: fillSize * 0.42, height: fillSize * 0.42)
                                    .transition(.opacity)
                            }
                        }
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                }
            }
            .background {
                if breathe && !isRecording && !reduceMotion {
                    BreathingRing(size: size, lineWidth: 2 * unit)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(dimmed && !isRecording ? 0.4 : 1)
        .handGestureShortcut(.primaryAction)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.8), value: isRecording)
        .animation(.easeInOut(duration: 0.2), value: showCheck)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }
}

/// A checkmark that draws itself in 0.35 s. Built from a trimmed path so it
/// works on every watchOS the app supports.
private struct DrawnCheck: View {
    let lineWidth: CGFloat
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(Color.black, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.35).delay(0.05)) { progress = 1 }
                }
            }
            .accessibilityHidden(true)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.15))
        return path
    }
}

/// A soft amber ring that breathes out from the button every 2.2 s, so a
/// first-time user knows to tap without any words on screen.
private struct BreathingRing: View {
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        PhaseAnimator([false, true]) { expanded in
            Circle()
                .stroke(Color.brandAmber, lineWidth: lineWidth)
                .frame(width: size, height: size)
                .scaleEffect(expanded ? 1.2 : 1)
                .opacity(expanded ? 0 : 0.7)
        } animation: { expanded in
            // Grow and fade out, then snap back unseen and go again
            expanded ? .easeOut(duration: 2.2) : nil
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        WatchRecordButtonView(size: 120, isRecording: false, breathe: true) {}
        WatchRecordButtonView(size: 120, isRecording: true, audioLevel: 0.5) {}
    }
}
