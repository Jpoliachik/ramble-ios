//
//  WebhookDestinationEditor.swift
//  Ramble
//

import SwiftUI

enum TestWebhookResult {
    case loading
    case success
    case failure(String)
}

/// Shared destination editor used by both onboarding and Settings. Renders
/// URL + Secret + API docs + Test, plus a Remove section when editing.
/// Test state lives inside this view so both call sites get it identically.
struct WebhookDestinationEditor: View {
    @Binding var draftURL: String
    @Binding var draftSecret: String
    @Binding var draftURLError: String?

    let isEditing: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onValidateURL: () -> Void
    let onRegenerate: () -> Void
    let onRemove: () -> Void

    @State private var testResult: TestWebhookResult?
    @State private var showSecretRevealed = false
    @State private var showSecretCopied = false
    @State private var showRegenerateConfirmation = false
    @State private var showRemoveConfirmation = false

    private var trimmedURL: String {
        draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTestLoading: Bool {
        if case .loading = testResult { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                urlSection
                if canSave {
                    testSection
                }
                secretSection
                docsSection
                if isEditing {
                    removeSection
                }
            }
            .navigationTitle(isEditing ? "Edit destination" : "Add destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add", action: onSave)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Regenerate secret?",
                isPresented: $showRegenerateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Regenerate", role: .destructive) {
                    onRegenerate()
                    HapticService.warning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your endpoint will need the new secret to accept requests.")
            }
            .confirmationDialog(
                "Remove destination?",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive, action: onRemove)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Transcripts will no longer be sent anywhere.")
            }
        }
    }

    private var urlSection: some View {
        Section {
            TextField("https://your-webhook.example.com", text: $draftURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: draftURL) { onValidateURL() }
            if let error = draftURLError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("URL")
        } footer: {
            Text("Make sure this is a valid URL that can receive POST requests.")
        }
    }

    private var secretSection: some View {
        Section {
            HStack {
                Text(showSecretRevealed ? draftSecret : String(repeating: "•", count: 24))
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
                UIPasteboard.general.string = draftSecret
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

            Button {
                showRegenerateConfirmation = true
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("Signing secret")
        } footer: {
            Text("For added security. Use this to optionally verify requests on your endpoint.")
        }
    }

    private var docsSection: some View {
        Section {
            Link(destination: URL(string: "https://goodloop.dev/ramble/docs")!) {
                HStack {
                    Label("Webhook setup docs", systemImage: "doc.text")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var testSection: some View {
        Section {
            Button(action: sendTest) {
                HStack {
                    switch testResult {
                    case .loading:
                        ProgressView().controlSize(.small)
                        Text("Sending…")
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Test delivered")
                    case .failure(let error):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Failed — \(error)")
                            .lineLimit(2)
                    case nil:
                        Image(systemName: "paperplane")
                        Text("Send test webhook")
                    }
                }
                .foregroundStyle(.primary)
            }
            .disabled(isTestLoading)
        }
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Remove destination", systemImage: "trash")
            }
        }
    }

    private func sendTest() {
        guard !trimmedURL.isEmpty,
              WebhookQueueService.validateWebhookURL(trimmedURL) == nil else { return }

        testResult = .loading
        Task {
            let error = await WebhookQueueService.shared.sendTestWebhook(
                urlOverride: trimmedURL,
                secretOverride: draftSecret
            )
            testResult = error.map { .failure($0) } ?? .success
            if case .success = testResult {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if case .success = testResult { testResult = nil }
            }
        }
    }
}
