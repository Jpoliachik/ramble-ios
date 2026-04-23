//
//  OnboardingWelcomeStep.swift
//  Ramble
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let namespace: Namespace.ID
    let onContinue: () -> Void

    @State private var heartbeat: CGFloat = 1.0
    @State private var wordmarkVisible = false
    @State private var titleVisible = false
    @State private var subtitleVisible = false
    @State private var ctaVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Red-dot + wordmark — matches MainView header
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 14, height: 14)
                    .scaleEffect(heartbeat)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }

                Text("Ramble")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .italic()
                    .opacity(wordmarkVisible ? 1 : 0)
                    .offset(x: wordmarkVisible ? 0 : -8)
            }

            Spacer().frame(height: 32)

            Text("Voice notes that go somewhere")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 8)

            Spacer().frame(height: 12)

            Text("Record on the go, get a clean transcript, pipe it into whatever you already use.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .opacity(subtitleVisible ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                OnboardingRedCircleButton(
                    systemImage: "arrow.right",
                    namespace: namespace,
                    action: onContinue
                )
                .opacity(ctaVisible ? 1 : 0)
                .scaleEffect(ctaVisible ? 1 : 0.7)

                Text("Let's get you set up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(ctaVisible ? 1 : 0)
            }
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            runEntrance()
            startHeartbeat()
        }
    }

    private func runEntrance() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15)) {
            wordmarkVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.45)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            subtitleVisible = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.95)) {
            ctaVisible = true
        }
    }

    private func startHeartbeat() {
        // Subtle heartbeat, ~70bpm. Small amplitude so it feels alive, not frantic.
        withAnimation(
            .easeInOut(duration: 0.85)
            .repeatForever(autoreverses: true)
        ) {
            heartbeat = 1.18
        }
    }
}

#Preview {
    OnboardingView()
}
