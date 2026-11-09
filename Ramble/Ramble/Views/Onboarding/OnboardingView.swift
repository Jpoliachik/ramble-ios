//
//  OnboardingView.swift
//  Ramble
//
//  First launch: three intro beats, pick where notes go, connect an agent
//  (copy → paste → waiting → connected, all on one screen), then get the
//  watch app. Microphone access is asked on the first iPhone recording, and
//  the transcription model lives in Settings.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("shouldShowOnboardingToast") private var shouldShowOnboardingToast: Bool = false

    @State private var step: OnboardingStep = .intro
    @State private var direction: TransitionDirection = .forward
    /// Set when the person saved a webhook instead of connecting an agent,
    /// so Back from the watch step returns to the destination step.
    @State private var skippedConnect = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Persistent nav row: the same view instance across body steps,
                // so only the active progress dot animates between them.
                if let activeStep = step.progressIndex {
                    OnboardingNavRow(activeStep: activeStep) {
                        if let previous = previousStep {
                            advance(to: previous)
                        }
                    }
                    .transition(.opacity)
                }

                Group {
                    switch step {
                    case .intro:
                        OnboardingIntroStep(
                            onContinue: {
                                giveConsent()
                                // iPad: straight to connecting an agent (webhooks live in Settings)
                                advance(to: ThisDevice.isPad ? .connect : .destination)
                            }
                        )
                    case .destination:
                        OnboardingDestinationStep(
                            onAddAgent: {
                                skippedConnect = false
                                advance(to: .connect)
                            },
                            onWebhookSaved: {
                                skippedConnect = true
                                afterDestination()
                            },
                            onLater: {
                                skippedConnect = true
                                afterDestination()
                            }
                        )
                    case .connect:
                        OnboardingConnectStep(
                            onContinue: afterDestination,
                            onLater: afterDestination
                        )
                    case .watch:
                        OnboardingWatchStep(onFinish: finish)
                    }
                }
                .transition(slideTransition)
                .id(step)
            }
        }
        .preferredColorScheme(nil)
    }

    private var previousStep: OnboardingStep? {
        switch step {
        case .intro: return nil
        case .destination: return .intro
        case .connect: return .destination
        case .watch: return skippedConnect ? .destination : .connect
        }
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

    /// "Get started" is the consent to cloud transcription. Only now does
    /// the phone set up with the server, connect the watch and upload.
    private func giveConsent() {
        Consent.give()
    }

    /// The watch step, except on iPad, where no watch can pair.
    private func afterDestination() {
        if ThisDevice.isPad {
            finish()
        } else {
            advance(to: .watch)
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
