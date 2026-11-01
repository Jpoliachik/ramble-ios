//
//  WatchRecordButtonView.swift
//  watch Watch App
//

import SwiftUI

struct WatchRecordButtonView: View {
    let isRecording: Bool
    var audioLevel: Float = 0
    let action: () -> Void

    private let buttonSize: CGFloat = 88

    // Bar configuration
    private let barWidth: CGFloat = 10
    private let barSpacing: CGFloat = 6
    private let barCornerRadius: CGFloat = 5
    private let minBarHeight: CGFloat = 10
    private let maxBarHeight: CGFloat = 38
    private let barScales: [CGFloat] = [0.7, 1.0, 0.8]

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        return minBarHeight + (maxBarHeight - minBarHeight) * level * barScales[index]
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Border ring
                Circle()
                    .stroke(Color.brandRed, lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                if isRecording {
                    // Animated audio level bars
                    HStack(spacing: barSpacing) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: barCornerRadius)
                                .fill(Color.brandRed)
                                .frame(width: barWidth, height: barHeight(for: index))
                        }
                    }
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: audioLevel)
                } else {
                    // Filled circle
                    Circle()
                        .fill(Color.brandRed)
                        .frame(width: buttonSize - 16, height: buttonSize - 16)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }
}

#Preview {
    VStack {
        WatchRecordButtonView(isRecording: false) {}
        WatchRecordButtonView(isRecording: true, audioLevel: 0.5) {}
    }
}
