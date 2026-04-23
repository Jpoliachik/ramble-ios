//
//  OnboardingTranscribeStep.swift
//  Ramble
//

import SwiftUI

struct OnboardingTranscribeStep: View {
    let namespace: Namespace.ID
    let onContinue: () -> Void

    @StateObject private var viewModel = OnboardingTranscribeViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 4)

            TypewriterPreview()
                .frame(height: 60)
                .padding(.horizontal, 28)
                .onboardingAppear(delay: 0.05)

            Spacer().frame(height: 8)

            OnboardingStepHeader(
                eyebrow: "Step 2 · Transcribe",
                title: "Your words, typed",
                subtitle: "Pick how Ramble turns audio into text. Apple Speech is free and on-device. Upgrade anytime for cloud accuracy."
            )

            Spacer().frame(height: 24)

            ScrollView {
                VStack(spacing: 10) {
                    TranscribeModelRow(
                        title: TranscriptionProvider.appleSpeech.displayName,
                        subtitle: appleSubtitle,
                        iconName: "iphone",
                        isSystemIcon: true,
                        isSelected: viewModel.isAppleSelected,
                        isLocked: false,
                        namespace: namespace,
                        onTap: viewModel.selectApple
                    )

                    ForEach(CloudModel.allCases) { model in
                        TranscribeModelRow(
                            title: model.displayName,
                            subtitle: shortSubtitle(for: model),
                            iconName: model.iconName,
                            isSystemIcon: false,
                            isSelected: viewModel.isSelected(cloudModel: model),
                            isLocked: !subscriptionService.isPremium,
                            namespace: namespace,
                            onTap: { viewModel.tapCloud(model) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onboardingAppear(delay: 0.35)

            Text("You can change this anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            OnboardingPrimaryButton(title: "Continue") {
                viewModel.commit()
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.showPaywall) {
            SubscriptionView()
        }
        .onChange(of: viewModel.showPaywall) { _, isShowing in
            if !isShowing {
                viewModel.applyPendingIfPurchased()
            }
        }
    }

    private var appleSubtitle: String {
        if #available(iOS 26.0, *) {
            return "On device · free · works offline"
        } else {
            return "On device · free · update to iOS 26 for better accuracy"
        }
    }

    private func shortSubtitle(for model: CloudModel) -> String {
        switch model {
        case .whisperLargeV3Turbo: return "Fast and accurate — all-around"
        case .whisperLargeV3: return "Best for accents and multilingual"
        case .deepgramNova3: return "Smart formatting, strong English"
        case .openAIGPT4oTranscribe: return "Highest accuracy in noise"
        }
    }
}

// MARK: - View Model

@MainActor
final class OnboardingTranscribeViewModel: ObservableObject {
    @Published var transcriptionProvider: TranscriptionProvider
    @Published var cloudModel: CloudModel
    @Published var showPaywall = false

    /// Cloud model tapped while locked — applied after successful purchase.
    private var pendingCloudModel: CloudModel?

    private let settingsService = SettingsService.shared

    init() {
        let loaded = SettingsService.shared.load()
        transcriptionProvider = loaded.transcriptionProvider
        cloudModel = loaded.cloudModel
    }

    var isAppleSelected: Bool {
        transcriptionProvider == .appleSpeech
    }

    func isSelected(cloudModel model: CloudModel) -> Bool {
        transcriptionProvider == .cloudTranscription && cloudModel == model
    }

    func selectApple() {
        HapticService.selection()
        transcriptionProvider = .appleSpeech
    }

    func tapCloud(_ model: CloudModel) {
        if SubscriptionService.shared.isPremium {
            HapticService.selection()
            transcriptionProvider = .cloudTranscription
            cloudModel = model
        } else {
            HapticService.warning()
            pendingCloudModel = model
            showPaywall = true
        }
    }

    func applyPendingIfPurchased() {
        guard let pending = pendingCloudModel else { return }
        pendingCloudModel = nil
        if SubscriptionService.shared.isPremium {
            transcriptionProvider = .cloudTranscription
            cloudModel = pending
        }
    }

    /// Persist the user's choice before advancing. Merges with existing settings
    /// so we don't clobber webhookSecret / deviceId / etc.
    func commit() {
        var current = settingsService.load()
        current.transcriptionProvider = transcriptionProvider
        current.cloudModel = cloudModel
        settingsService.save(current)
    }
}

// MARK: - Model Row

private struct TranscribeModelRow: View {
    let title: String
    let subtitle: String
    let iconName: String
    let isSystemIcon: Bool
    let isSelected: Bool
    let isLocked: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void

    @State private var lockShake: CGFloat = 0

    var body: some View {
        Button {
            if isLocked {
                triggerShake()
            }
            onTap()
        } label: {
            HStack(spacing: 14) {
                iconBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                trailingIndicator
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
            )
            .offset(x: lockShake)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }

    @ViewBuilder
    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 36, height: 36)
            if isSystemIcon {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.primary)
            } else {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 14, height: 14)
                    .matchedGeometryEffect(id: "onboarding.redDot", in: namespace)
            }
        } else if isLocked {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Circle()
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }

    private func triggerShake() {
        let values: [CGFloat] = [-6, 6, -4, 4, 0]
        for (i, v) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                withAnimation(.easeInOut(duration: 0.04)) {
                    lockShake = v
                }
            }
        }
    }
}

// MARK: - Typewriter preview

private struct TypewriterPreview: View {
    private let phrases = [
        "So the thing I was thinking about today…",
        "Remind me to follow up with Maya about the deck.",
        "Idea: what if we shipped the smaller version first?"
    ]

    @State private var phraseIndex = 0
    @State private var displayed = ""
    @State private var isTyping = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text(displayed + (isTyping ? "▍" : ""))
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: displayed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .task {
            while !Task.isCancelled {
                let phrase = phrases[phraseIndex]
                await typeOut(phrase)
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if Task.isCancelled { break }
                await clearOut()
                try? await Task.sleep(nanoseconds: 200_000_000)
                phraseIndex = (phraseIndex + 1) % phrases.count
            }
        }
    }

    @MainActor
    private func typeOut(_ phrase: String) async {
        isTyping = true
        for i in phrase.indices {
            if Task.isCancelled { return }
            displayed = String(phrase[..<phrase.index(after: i)])
            try? await Task.sleep(nanoseconds: 38_000_000)
        }
        isTyping = false
    }

    @MainActor
    private func clearOut() async {
        isTyping = true
        while !displayed.isEmpty {
            if Task.isCancelled { return }
            displayed.removeLast()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        isTyping = false
    }
}

#Preview {
    OnboardingView()
}
