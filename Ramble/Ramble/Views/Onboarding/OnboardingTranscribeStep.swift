//
//  OnboardingTranscribeStep.swift
//  Ramble
//

import Combine
import SwiftUI

struct OnboardingTranscribeStep: View {
    let onContinue: () -> Void

    @StateObject private var viewModel = OnboardingTranscribeViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)

                OnboardingIllustration(name: "illustration-transcribe")
                    .onboardingAppear(delay: 0.05)

                Spacer().frame(height: 14)

                VStack(spacing: 12) {
                    OnboardingHeadline(size: 34) {
                        Text("Voice ") + Text("in").italic() + Text(", words ") + Text("back").italic() + Text(".")
                    }

                    OnboardingBody(text: "Apple Speech is free and on-device. Cloud models are sharper — pick one if accuracy matters.")
                }
                .padding(.horizontal, 24)
                .onboardingAppear(delay: 0.2)

                Spacer().frame(height: 22)

                VStack(alignment: .leading, spacing: 0) {
                    OnboardingSectionHeader(title: "Free · on-device")
                    appleRow
                        .padding(.bottom, 24)

                    OnboardingSectionHeader(title: "Cloud · premium", trailing: "$2.99 / month")
                    cloudRows

                    Text("Cloud transcription routes through our open-source proxy. No audio or text is stored on our servers.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                .onboardingAppear(delay: 0.35)

                Spacer(minLength: 24)
            }
        } bottomBar: {
            OnboardingPrimaryButton(title: continueTitle) {
                viewModel.commit()
                onContinue()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            SubscriptionView()
        }
        .onChange(of: viewModel.showPaywall) { _, isShowing in
            if !isShowing {
                viewModel.applyPendingIfPurchased()
            }
        }
    }

    private var continueTitle: String {
        let cloudSelectedButLocked = viewModel.transcriptionProvider == .cloudTranscription
            && !subscriptionService.isPremium
        return cloudSelectedButLocked ? "Subscribe & Continue" : "Continue"
    }

    // MARK: - Free row

    private var appleRow: some View {
        VStack(spacing: 0) {
            TranscriptionModelRow(
                title: TranscriptionProvider.appleSpeech.displayName,
                subtitle: appleSubtitle,
                logo: .system("iphone"),
                isSelected: viewModel.isAppleSelected,
                onTap: viewModel.selectApple
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obSurface)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Cloud rows

    private var cloudRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(CloudModel.allCases.enumerated()), id: \.element.id) { index, model in
                TranscriptionModelRow(
                    title: model.displayName,
                    subtitle: shortSubtitle(for: model),
                    logo: .asset(model.iconName),
                    isSelected: viewModel.isSelected(cloudModel: model),
                    isLocked: !subscriptionService.isPremium,
                    showsRecommended: model == .whisperLargeV3Turbo,
                    onTap: { viewModel.tapCloud(model) }
                )

                if index < CloudModel.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.obHair)
                        .frame(height: 0.5)
                        .padding(.leading, 50)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obSurface)
        )
        .padding(.horizontal, 16)
    }

    private var appleSubtitle: String {
        if #available(iOS 26.0, *) {
            return "Built into iOS · works offline"
        } else {
            return "Update to iOS 26 for better accuracy"
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
            // Don't change the selection until the user actually subscribes —
            // otherwise canceling the paywall leaves a locked row "selected".
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

#Preview {
    OnboardingView()
}
