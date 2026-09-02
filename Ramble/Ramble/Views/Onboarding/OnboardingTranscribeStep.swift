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
                    OnboardingHeadline(size: 32) {
                        Text("Voice ") + Text("in").italic() + Text(", words ") + Text("back").italic() + Text(".")
                    }

                    OnboardingBody(text: "Choose your model. Apple Speech is free and instant. Whisper is free too, and stays on-device after a one-time download. Cloud models are sharper - if accuracy is important.")
                }
                .padding(.horizontal, 24)
                .onboardingAppear(delay: 0.2)

                Spacer().frame(height: 22)

                VStack(alignment: .leading, spacing: 0) {
                    OnboardingSectionHeader(title: "Free · on-device")
                    appleRow
                        .padding(.bottom, 24)

                    OnboardingSectionHeader(
                        title: "Cloud · premium",
                        trailing: subscriptionService.isPremium ? nil : "$3.99 / month"
                    )
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

    private var appleRow: some View {
        BrandCard {
            AppleSpeechRow(
                isSelected: viewModel.isAppleSelected,
                onTap: viewModel.selectApple
            )
            ForEach(LocalWhisperModel.allCases) { model in
                BrandRowDivider()
                LocalWhisperRow(
                    model: model,
                    isSelected: viewModel.isLocalWhisperSelected(model),
                    onTap: { viewModel.selectLocalWhisper(model) }
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private var cloudRows: some View {
        BrandCard {
            ForEach(Array(CloudModel.allCases.enumerated()), id: \.element.id) { index, model in
                CloudModelRow(
                    model: model,
                    isSelected: viewModel.isSelected(cloudModel: model),
                    isLocked: !subscriptionService.isPremium,
                    onTap: { viewModel.tapCloud(model) }
                )

                if index < CloudModel.allCases.count - 1 {
                    BrandRowDivider()
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - View Model

@MainActor
final class OnboardingTranscribeViewModel: ObservableObject {
    @Published var transcriptionProvider: TranscriptionProvider
    @Published var cloudModel: CloudModel
    @Published var localWhisperModel: LocalWhisperModel
    @Published var showPaywall = false

    /// Cloud model tapped while locked — applied after successful purchase.
    private var pendingCloudModel: CloudModel?

    private let settingsService = SettingsService.shared

    init() {
        let loaded = SettingsService.shared.load()
        transcriptionProvider = loaded.transcriptionProvider
        cloudModel = loaded.cloudModel
        localWhisperModel = loaded.localWhisperModel
    }

    var isAppleSelected: Bool {
        transcriptionProvider == .appleSpeech
    }

    func isSelected(cloudModel model: CloudModel) -> Bool {
        transcriptionProvider == .cloudTranscription && cloudModel == model
    }

    func isLocalWhisperSelected(_ model: LocalWhisperModel) -> Bool {
        transcriptionProvider == .localWhisper && localWhisperModel == model
    }

    func selectApple() {
        HapticService.selection()
        transcriptionProvider = .appleSpeech
    }

    /// `LocalWhisperRow` starts the model download itself; this only records the
    /// choice, which `commit()` persists when the user advances.
    func selectLocalWhisper(_ model: LocalWhisperModel) {
        HapticService.selection()
        transcriptionProvider = .localWhisper
        localWhisperModel = model
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
        current.localWhisperModel = localWhisperModel
        settingsService.save(current)
    }
}

#Preview {
    OnboardingView()
}
