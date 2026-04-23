//
//  OnboardingComponents.swift
//  Ramble
//

import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case record
    case transcribe
    case send

    var showsProgress: Bool {
        self != .welcome
    }

    /// Progress index (0-based) among the three post-welcome steps.
    var progressIndex: Int? {
        switch self {
        case .welcome: return nil
        case .record: return 0
        case .transcribe: return 1
        case .send: return 2
        }
    }

    static var progressCount: Int { 3 }
}

/// Three-dot progress indicator with a single traveling filled dot.
struct OnboardingProgressDots: View {
    let activeIndex: Int
    let namespace: Namespace.ID

    private let dotSize: CGFloat = 7
    private let spacing: CGFloat = 10

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<OnboardingStep.progressCount, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)

                    if index == activeIndex {
                        Circle()
                            .fill(Color.red)
                            .frame(width: dotSize, height: dotSize)
                            .matchedGeometryEffect(id: "onboarding.progress.active", in: namespace)
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: activeIndex)
    }
}

/// The persistent red circle that travels between screens as the CTA.
/// Uses matchedGeometryEffect so it morphs across step transitions.
struct OnboardingRedCircleButton: View {
    let systemImage: String
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var pulse = false
    @State private var idleNudge = false

    private let size: CGFloat = 72

    var body: some View {
        Button(action: {
            HapticService.buttonTap()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: size + 24, height: size + 24)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.0 : 0.7)

                Circle()
                    .fill(Color.red)
                    .frame(width: size, height: size)
                    .matchedGeometryEffect(id: "onboarding.redDot", in: namespace)

                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: idleNudge ? 4 : 0)
            }
            .frame(width: size + 32, height: size + 32)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                startIdleNudge()
            }
        }
    }

    private func startIdleNudge() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            idleNudge = true
        }
    }
}

/// Shared container providing consistent vertical layout + top progress bar.
struct OnboardingStepContainer<Content: View>: View {
    let step: OnboardingStep
    let namespace: Namespace.ID
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if step.showsProgress, let activeIndex = step.progressIndex {
                OnboardingProgressDots(activeIndex: activeIndex, namespace: namespace)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 40)
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Fades + slides content up on appear, with a staggered delay.
struct OnboardingAppearModifier: ViewModifier {
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func onboardingAppear(delay: Double = 0) -> some View {
        modifier(OnboardingAppearModifier(delay: delay))
    }
}

/// Large title + subtitle header shared across steps 2–4.
struct OnboardingStepHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .onboardingAppear(delay: 0.05)
            }

            Text(title)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(.primary)
                .onboardingAppear(delay: 0.15)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .onboardingAppear(delay: 0.25)
        }
    }
}

/// Shared bottom continue button — mirrors the red dot's visual language but rectangular.
struct OnboardingPrimaryButton: View {
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    init(title: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button {
            HapticService.buttonTap()
            action()
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isDisabled ? Color.red.opacity(0.4) : Color.red)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

