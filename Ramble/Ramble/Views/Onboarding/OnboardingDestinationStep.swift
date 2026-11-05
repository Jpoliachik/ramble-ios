//
//  OnboardingDestinationStep.swift
//  Ramble
//
//  "Where should notes go?" One "Your agent" card (every agent uses the same
//  connect flow, so there's no picker) and a quiet "Any webhook" row that
//  opens the existing webhook editor. Saving a webhook skips the connect step.
//

import Combine
import SwiftUI

struct OnboardingDestinationStep: View {
    let onAddAgent: () -> Void
    let onWebhookSaved: () -> Void
    let onLater: () -> Void

    @StateObject private var viewModel = OnboardingSendViewModel()

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingHeadline(size: 34, alignment: .leading) {
                        Text("Where should ") + Text("notes go?").italic().foregroundColor(Color.obInkSoft)
                    }
                    OnboardingBody(text: "You can change this later.", maxWidth: nil, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .onboardingAppear(delay: 0.05)

                VStack(spacing: 10) {
                    agentCard
                    webhookRow
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .onboardingAppear(delay: 0.15)

                Spacer(minLength: 24)
            }
        } bottomBar: {
            VStack(spacing: 0) {
                OnboardingPrimaryButton(title: "Add your agent", action: onAddAgent)
                OnboardingSecondaryLink(title: "Set up later", action: onLater)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $viewModel.showEditSheet, onDismiss: webhookSheetDismissed) {
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
            .presentationDetents([.large])
        }
    }

    // MARK: - Agent card

    private var agentCard: some View {
        Button(action: {
            HapticService.buttonTap()
            onAddAgent()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandAmber)
                        .frame(width: 36, height: 36)
                        .background(Color.brandAmberSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("Your agent")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.obInk)
                    Spacer()
                }

                Text("Sets itself up from one message.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.obInkSoft)

                Rectangle()
                    .fill(Color.obHair)
                    .frame(height: 1)

                // Names only for now. Official marks can sit to the left once
                // each brand's usage rules are checked.
                Text("Works with Muse, Grok Bot, ChatGPT and more")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.brandAmber, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Connect your agent")
    }

    // MARK: - Webhook row

    private var webhookRow: some View {
        Button(action: {
            HapticService.buttonTap()
            if viewModel.hasDestination {
                viewModel.beginEdit()
            } else {
                viewModel.beginAdd()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.obInkSoft)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(viewModel.hasDestination ? viewModel.destinationLabel : "Any webhook")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.obInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func webhookSheetDismissed() {
        viewModel.commit()
        guard viewModel.hasDestination else { return }
        onWebhookSaved()
    }
}

// MARK: - View Model

@MainActor
final class OnboardingSendViewModel: ObservableObject {
    @Published var destinationURL: String = ""
    @Published var destinationSecret: String = ""
    @Published var showEditSheet = false
    @Published var webhookHealth: WebhookHealth = .untested

    /// Sheet-local draft values so cancelling doesn't trash saved state.
    @Published var draftURL: String = ""
    @Published var draftSecret: String = ""
    @Published var draftURLError: String?

    private let settingsService = SettingsService.shared
    private let storageService = StorageService.shared

    init() {
        let loaded = settingsService.load()
        destinationURL = loaded.webhookURL ?? ""
        destinationSecret = loaded.webhookSecret
        webhookHealth = WebhookHealth.compute(from: storageService.loadRecordings())
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
