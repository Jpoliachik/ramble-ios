//
//  OnboardingSendStep.swift
//  Ramble
//

import SwiftUI

struct OnboardingSendStep: View {
    let namespace: Namespace.ID
    let onFinish: () -> Void

    @StateObject private var viewModel = OnboardingSendViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            SendIllustration()
                .frame(height: 96)
                .onboardingAppear(delay: 0.05)

            Spacer().frame(height: 16)

            OnboardingStepHeader(
                eyebrow: "Step 3 · Send",
                title: "Where it lands",
                subtitle: "Ramble can auto-deliver every transcript to a URL you control — perfect for your notes app, automations, or an AI agent. Totally optional."
            )

            Spacer()

            Group {
                if viewModel.hasDestination {
                    destinationRow
                } else {
                    addDestinationButton
                }
            }
            .padding(.horizontal, 24)
            .onboardingAppear(delay: 0.3)

            Spacer()

            VStack(spacing: 4) {
                OnboardingPrimaryButton(title: viewModel.hasDestination ? "All set" : "Maybe later") {
                    viewModel.commit()
                    HapticService.success()
                    onFinish()
                }
                if !viewModel.hasDestination {
                    Text("You can always add one in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.showEditSheet) {
            DestinationEditSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var addDestinationButton: some View {
        Button {
            HapticService.buttonTap()
            viewModel.beginAdd()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Add a destination")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    private var destinationRow: some View {
        Button {
            HapticService.buttonTap()
            viewModel.beginEdit()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.destinationLabel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Tap to edit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "pencil")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
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

    /// Persists to settings. Enables webhook when a URL is present.
    func commit() {
        var current = settingsService.load()
        if destinationURL.isEmpty {
            current.webhookURL = nil
            current.webhookEnabled = false
        } else {
            current.webhookURL = destinationURL
            current.webhookSecret = destinationSecret
            current.webhookEnabled = true
        }
        settingsService.save(current)
    }
}

// MARK: - Destination edit sheet

private struct DestinationEditSheet: View {
    @ObservedObject var viewModel: OnboardingSendViewModel

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
                    Text("URL")
                } footer: {
                    Text("Ramble will POST each transcript as JSON to this URL.")
                }

                Section {
                    Text(viewModel.draftSecret)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        UIPasteboard.general.string = viewModel.draftSecret
                        HapticService.success()
                    } label: {
                        Label("Copy secret", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("Signing secret")
                } footer: {
                    Text("Use this to verify requests on your endpoint.")
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

// MARK: - Illustration

private struct SendIllustration: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Soft halo
            Circle()
                .fill(Color.red.opacity(0.08))
                .frame(width: 92, height: 92)

            Image(systemName: "paperplane.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(-20))
                .offset(x: pulse ? 6 : -6, y: pulse ? -4 : 4)
                .shadow(color: .red.opacity(0.25), radius: 8, y: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    OnboardingView()
}
