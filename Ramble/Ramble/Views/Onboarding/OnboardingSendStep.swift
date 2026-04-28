//
//  OnboardingSendStep.swift
//  Ramble
//

import Combine
import SwiftUI

struct OnboardingSendStep: View {
    let onFinish: () -> Void

    @StateObject private var viewModel = OnboardingSendViewModel()

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)

                OnboardingIllustration(name: "illustration-automate")
                    .onboardingAppear(delay: 0.05)

                Spacer().frame(height: 14)

                VStack(spacing: 16) {
                    OnboardingHeadline(size: 32) {
                        Text("Now, make it ") + Text("do something.").italic()
                    }

                    OnboardingBody(text: "Pipe every transcript straight to your API. Connect to your notes system, an automation platform, AI agent - anywhere.")
                }
                .padding(.horizontal, 24)
                .onboardingAppear(delay: 0.2)

                Spacer().frame(height: 24)

                SendVisual()
                    .padding(.horizontal, 16)
                    .onboardingAppear(delay: 0.3)

                Spacer().frame(height: 20)

                if viewModel.hasDestination {
                    destinationRow
                        .padding(.horizontal, 16)
                        .onboardingAppear(delay: 0.4)
                } else {
                    addDestinationCard
                        .padding(.horizontal, 16)
                        .onboardingAppear(delay: 0.4)
                }

                Spacer(minLength: 24)
            }
        } bottomBar: {
            VStack(spacing: 8) {
                OnboardingSurfaceButton(
                    title: viewModel.hasDestination ? "Continue" : "Maybe later"
                ) {
                    viewModel.commit()
                    HapticService.success()
                    onFinish()
                }

                if !viewModel.hasDestination {
                    Text("You can always add one in Settings.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $viewModel.showEditSheet) {
            DestinationEditSheet(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationBackgroundInteraction(.disabled)
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled(false)
        }
    }

    private var addDestinationCard: some View {
        BrandPlusActionCard(title: "Add a destination") {
            viewModel.beginAdd()
        }
    }

    // MARK: - Destination row (set state)

    private var destinationRow: some View {
        Button {
            HapticService.buttonTap()
            viewModel.beginEdit()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.brandRed)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.destinationLabel)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.obInk)
                    Text("Tap to edit")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }

                Spacer()

                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Model

@MainActor
final class OnboardingSendViewModel: ObservableObject {
    @Published var destinationURL: String = ""
    @Published var destinationSecret: String = ""
    @Published var showEditSheet = false

    /// Sheet-local draft values so cancelling doesn't trash saved state.
    @Published var draftURL: String = ""
    @Published var draftSecret: String = ""
    @Published var draftURLError: String?

    private let settingsService = SettingsService.shared

    init() {
        let loaded = settingsService.load()
        destinationURL = loaded.webhookURL ?? ""
        destinationSecret = loaded.webhookSecret
    }

    var hasDestination: Bool {
        !destinationURL.isEmpty
    }

    var destinationLabel: String {
        guard let host = URL(string: destinationURL)?.host else {
            return destinationURL
        }
        return host
    }

    func beginAdd() {
        draftURL = ""
        draftSecret = destinationSecret.isEmpty ? Settings.generateSecret() : destinationSecret
        draftURLError = nil
        showEditSheet = true
    }

    func beginEdit() {
        draftURL = destinationURL
        draftSecret = destinationSecret
        draftURLError = nil
        showEditSheet = true
    }

    func validateDraftURL() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draftURLError = nil
            return
        }
        draftURLError = WebhookQueueService.validateWebhookURL(trimmed)
    }

    var canSaveDraft: Bool {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && draftURLError == nil
    }

    func saveDraft() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, draftURLError == nil else { return }
        destinationURL = trimmed
        destinationSecret = draftSecret.isEmpty ? Settings.generateSecret() : draftSecret
        HapticService.success()
        showEditSheet = false
    }

    func cancelDraft() {
        showEditSheet = false
    }

    func regenerateDraftSecret() {
        draftSecret = Settings.generateSecret()
    }

    func removeDestination() {
        destinationURL = ""
        destinationSecret = Settings.generateSecret()
        HapticService.success()
        showEditSheet = false
    }

    func commit() {
        var current = settingsService.load()
        if destinationURL.isEmpty {
            current.webhookURL = nil
        } else {
            current.webhookURL = destinationURL
            current.webhookSecret = destinationSecret
        }
        settingsService.save(current)
    }
}

// MARK: - Destination edit sheet

private struct DestinationEditSheet: View {
    @ObservedObject var viewModel: OnboardingSendViewModel

    var body: some View {
        WebhookDestinationEditor(
            draftURL: $viewModel.draftURL,
            draftSecret: $viewModel.draftSecret,
            draftURLError: $viewModel.draftURLError,
            isEditing: viewModel.hasDestination,
            canSave: viewModel.canSaveDraft,
            onSave: viewModel.saveDraft,
            onCancel: viewModel.cancelDraft,
            onValidateURL: viewModel.validateDraftURL,
            onRegenerate: viewModel.regenerateDraftSecret,
            onRemove: viewModel.removeDestination
        )
    }
}

#Preview {
    OnboardingView()
}
