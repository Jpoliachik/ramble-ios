//
//  OnboardingView.swift
//  Ramble
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State private var step: OnboardingStep = .welcome
    @Namespace private var namespace

    var body: some View {
        ZStack {
            // Subtle warm radial backdrop — barely perceptible, but premium.
            OnboardingBackdrop()
                .ignoresSafeArea()

            OnboardingStepContainer(step: step, namespace: namespace) {
                Group {
                    switch step {
                    case .welcome:
                        OnboardingWelcomeStep(namespace: namespace) {
                            advance(to: .record)
                        }
                    case .record:
                        OnboardingRecordStep(namespace: namespace) {
                            advance(to: .transcribe)
                        }
                    case .transcribe:
                        OnboardingTranscribeStep(namespace: namespace) {
                            advance(to: .send)
                        }
                    case .send:
                        OnboardingSendStep(namespace: namespace) {
                            finish()
                        }
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
                .id(step)
            }
        }
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            step = next
        }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.45)) {
            hasCompletedOnboarding = true
        }
    }
}

/// Slow warm→cool radial gradient that drifts imperceptibly behind the whole flow.
private struct OnboardingBackdrop: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [
                    Color.red.opacity(0.08),
                    Color.red.opacity(0.0),
                    Color(.systemBackground)
                ],
                center: UnitPoint(x: 0.5 + 0.1 * phase, y: 0.15 - 0.05 * phase),
                startRadius: 60,
                endRadius: max(geo.size.width, geo.size.height)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
