//
//  WatchRecordButtonView.swift
//  watch Watch App
//

import SwiftUI

struct WatchRecordButtonView: View {
    let isRecording: Bool
    var audioLevel: Float = 0
    let action: () -> Void

    private let buttonSize: CGFloat = 80

    // Bar configuration
    private let barWidth: CGFloat = 10
    private let barSpacing: CGFloat = 6
    private let barCornerRadius: CGFloat = 5
    private let minBarHeight: CGFloat = 10
    private let maxBarHeight: CGFloat = 36
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
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                if isRecording {
                    // Animated audio level bars
                    HStack(spacing: barSpacing) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: barCornerRadius)
                                .fill(Color.red)
                                .frame(width: barWidth, height: barHeight(for: index))
                        }
                    }
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: audioLevel)
                } else {
                    // Filled circle
                    Circle()
                        .fill(Color.red)
                        .frame(width: buttonSize - 16, height: buttonSize - 16)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
}

#Preview {
    VStack {
        WatchRecordButtonView(isRecording: false) {}
        WatchRecordButtonView(isRecording: true, audioLevel: 0.5) {}
    }
}
