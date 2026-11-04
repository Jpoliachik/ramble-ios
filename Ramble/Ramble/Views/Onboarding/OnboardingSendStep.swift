//
//  OnboardingSendStep.swift
//  Ramble
//

import Combine
import SwiftUI

struct OnboardingSendStep: View {
    let onFinish: () -> Void

    @StateObject private var viewModel = OnboardingSendViewModel()
    @ObservedObject private var relay = RelayService.shared
    @State private var showConnectAgent = false

    private var hasAgent: Bool { !relay.connections.isEmpty }
    private var canContinue: Bool { hasAgent || viewModel.hasDestination }

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)

                OnboardingIllustration(name: "illustration-automate")
                    .onboardingAppear(delay: 0.05)

                Spacer().frame(height: 14)

                VStack(spacing: 16) {
                    OnboardingHeadline(size: 32) {
                        Text("Now, hand it to ") + Text("your agent.").italic()
                    }

                    OnboardingBody(text: "Every transcript goes to your agent to handle later. Connect it once with a short message, then just talk.")
                }
                .padding(.horizontal, 24)
                .onboardingAppear(delay: 0.2)

                Spacer().frame(height: 24)

                SendVisual(endpointText: hasAgent || !viewModel.hasDestination
                           ? "your agent"
                           : SendVisual.endpointText(for: viewModel.destinationURL))
                    .padding(.horizontal, 16)
                    .onboardingAppear(delay: 0.3)

                Spacer().frame(height: 20)

                VStack(spacing: 10) {
                    if hasAgent {
                        agentConnectedRow
                    } else {
                        BrandPlusActionCard(title: "Connect your agent") {
                            showConnectAgent = true
                        }
                    }

                    if viewModel.hasDestination {
                        destinationRow
                    } else {
                        Button {
                            HapticService.buttonTap()
                            viewModel.beginAdd()
                        } label: {
                            Text("Or send to a webhook")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.obInkSoft)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .onboardingAppear(delay: 0.4)

                Spacer(minLength: 24)
            }
        } bottomBar: {
            VStack(spacing: 8) {
                if canContinue {
                    OnboardingPrimaryButton(title: "Continue") {
                        viewModel.commit()
                        HapticService.success()
                        onFinish()
                    }
                } else {
                    OnboardingSurfaceButton(title: "Maybe later") {
                        viewModel.commit()
                        HapticService.success()
                        onFinish()
                    }

                    Text("You can always connect one in Settings.")
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
        .sheet(isPresented: $showConnectAgent) {
            ConnectAgentView()
        }
    }

    // MARK: - Agent row (connected state)

    private var agentConnectedRow: some View {
        Button {
            HapticService.buttonTap()
            showConnectAgent = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandAmber)
                    .frame(width: 26, height: 26)
                    .background(Color.brandAmberSoft, in: Circle())

                Text(relay.connections.count > 1 ? "Agents connected" : "Agent connected")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.obInk)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Destination row (set state)

    private var destinationRow: some View {
        Button {
            HapticService.buttonTap()
            viewModel.beginEdit()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(viewModel.webhookHealth.color)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(viewModel.webhookHealth.accessibilityLabel)

                Text(viewModel.destinationLabel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.obInk)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemGroupedBackground))
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
