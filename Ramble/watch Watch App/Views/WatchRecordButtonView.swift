//
//  WatchRecordButtonView.swift
//  watch Watch App
//

import SwiftUI

struct WatchRecordButtonView: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize: CGFloat = 80

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                RoundedRectangle(cornerRadius: isRecording ? 8 : buttonSize / 2)
                    .fill(Color.red)
                    .frame(
                        width: isRecording ? 24 : buttonSize - 16,
                        height: isRecording ? 24 : buttonSize - 16
                    )
                    .scaleEffect(isRecording ? pulseScale : 1.0)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
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
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.2
        }
    }
}

#Preview {
    VStack {
        WatchRecordButtonView(isRecording: false) {}
        WatchRecordButtonView(isRecording: true) {}
    }
}
