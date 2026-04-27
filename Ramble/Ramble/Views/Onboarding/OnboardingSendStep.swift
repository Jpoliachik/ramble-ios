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
                    OnboardingHeadline(size: 34) {
                        Text("Make it ") + Text("do something.").italic()
                    }

                    OnboardingBody(text: "Pipe every transcript into a URL you control — your notes, an automation, an AI agent. Optional.")
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

    // MARK: - Add destination (dashed card)

    private var addDestinationCard: some View {
        Button {
            HapticService.buttonTap()
            viewModel.beginAdd()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.obInk)
                        .frame(width: 28, height: 28)

                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.obBg)
                }

                Text("Add a destination")
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.obSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.obInk.opacity(0.08), lineWidth: 1)
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
                    .fill(Color.obSurface)
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

    var isEditing: Bool {
        hasDestination
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
    @State private var showSecretRevealed = false
    @State private var showSecretCopied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-webhook.example.com", text: $viewModel.draftURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.draftURL) {
                            viewModel.validateDraftURL()
                        }
                    if let error = viewModel.draftURLError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Your URL")
                } footer: {
                    Text("This is yours — your server, your workflow, your data. Transcripts go only here, never anywhere else.")
                }

                Section {
                    HStack {
                        Text(showSecretRevealed ? viewModel.draftSecret : String(repeating: "•", count: 24))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            withAnimation { showSecretRevealed.toggle() }
                        } label: {
                            Image(systemName: showSecretRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    Button {
                        UIPasteboard.general.string = viewModel.draftSecret
                        HapticService.success()
                        showSecretCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            showSecretCopied = false
                        }
                    } label: {
                        Label(
                            showSecretCopied ? "Copied" : "Copy secret",
                            systemImage: showSecretCopied ? "checkmark" : "doc.on.doc"
                        )
                        .foregroundStyle(showSecretCopied ? .green : .primary)
                    }
                } header: {
                    Text("Signing secret")
                } footer: {
                    Text("Use this to verify requests on your endpoint.")
                }

                Section {
                    Link(destination: URL(string: "https://goodloop.dev/ramble/docs")!) {
                        HStack {
                            Label("API setup docs", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit destination" : "Add destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelDraft()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "Save" : "Add") {
                        viewModel.saveDraft()
                    }
                    .disabled(!viewModel.canSaveDraft)
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
