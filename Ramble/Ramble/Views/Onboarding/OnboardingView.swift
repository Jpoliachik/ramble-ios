//
//  OnboardingView.swift
//  Ramble
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("shouldShowOnboardingToast") private var shouldShowOnboardingToast: Bool = false

    @State private var step: OnboardingStep = .welcome
    @State private var direction: TransitionDirection = .forward

    var body: some View {
        ZStack {
            Color.obBg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Persistent nav row — fades in/out when moving between Welcome and the body
                // steps, but is the *same* view instance across body steps so only the active
                // dot animates between transitions.
                if let activeStep = step.progressIndex {
                    OnboardingNavRow(activeStep: activeStep) {
                        if let previous = step.previous {
                            advance(to: previous)
                        }
                    }
                    .transition(.opacity)
                }

                Group {
                    switch step {
                    case .welcome:
                        OnboardingWelcomeStep(
                            onContinue: { advance(to: .record) }
                        )
                    case .record:
                        OnboardingRecordStep(
                            onPermissionGranted: { advance(to: .transcribe) }
                        )
                    case .transcribe:
                        OnboardingTranscribeStep(
                            onContinue: { advance(to: .send) }
                        )
                    case .send:
                        OnboardingSendStep(
                            onFinish: finish
                        )
                    }
                }
                .transition(slideTransition)
                .id(step)
            }
        }
        .preferredColorScheme(nil)
    }

    private var slideTransition: AnyTransition {
        switch direction {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func advance(to next: OnboardingStep) {
        direction = next.rawValue > step.rawValue ? .forward : .backward
        withAnimation(.smooth(duration: 0.3)) {
            step = next
        }
    }

    private func finish() {
        shouldShowOnboardingToast = true
        withAnimation(.easeInOut(duration: 0.4)) {
            hasCompletedOnboarding = true
        }
    }
}

private enum TransitionDirection {
    case forward
    case backward
}

#Preview {
    OnboardingView()
}
