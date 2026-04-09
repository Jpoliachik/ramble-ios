//
//  SettingsView.swift
//  Ramble
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showExportShare = false
    @State private var showSecretCopied = false
    @State private var showRegenerateConfirmation = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationView {
            Form {
                transcriptionSection
                webhookSection
                statsSection
                exportSection
                dangerZoneSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.save()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSubscriptionPaywall) {
                SubscriptionView()
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    private var transcriptionSection: some View {
        Section {
            // Apple Speech — always available
            ProviderRowView(
                provider: .appleSpeech,
                isSelected: viewModel.transcriptionProvider == .appleSpeech,
                onSelect: { viewModel.transcriptionProvider = .appleSpeech }
            )

            // Cloud Transcription — gated behind subscription
            ProviderRowView(
                provider: .cloudTranscription,
                isSelected: viewModel.transcriptionProvider == .cloudTranscription,
                isPremiumLocked: !SubscriptionService.shared.isPremium,
                onSelect: { viewModel.selectCloudTranscription() }
            )

            // Model picker — visible when premium + cloud selected
            if viewModel.transcriptionProvider == .cloudTranscription
                && SubscriptionService.shared.isPremium
            {
                Picker("Model", selection: $viewModel.cloudModel) {
                    ForEach(CloudModel.allCases) { model in
                        Text(model.displayName)
                            .tag(model)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Transcription")
        }
    }

    private var webhookSection: some View {
        Section {
            Toggle("Post-Transcription Webhook", isOn: $viewModel.webhookEnabled)

            if viewModel.webhookEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Webhook URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://your-webhook.example.com", text: $viewModel.webhookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.webhookURL) {
                            viewModel.validateWebhookURL()
                        }

                    if let error = viewModel.webhookURLError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Test webhook button
                if !viewModel.webhookURL.isEmpty && viewModel.webhookURLError == nil {
                    Button {
                        viewModel.sendTestWebhook()
                    } label: {
                        HStack {
                            switch viewModel.testWebhookResult {
                            case .loading:
                                ProgressView()
                                    .controlSize(.small)
                                Text("Sending...")
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Test delivered")
                            case .failure(let error):
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text("Failed — \(error)")
                            case nil:
                                Image(systemName: "paperplane")
                                Text("Send Test Webhook")
                            }
                        }
                    }
                    .disabled(viewModel.testWebhookResult != nil && {
                        if case .loading = viewModel.testWebhookResult { return true }
                        return false
                    }())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Signing Secret")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(viewModel.webhookSecret)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = viewModel.webhookSecret
                            showSecretCopied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                showSecretCopied = false
                            }
                        } label: {
                            Label {
                                Text("Copy")
                            } icon: {
                                Image(systemName: showSecretCopied ? "checkmark" : "doc.on.doc")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(showSecretCopied ? .green : nil)

                        Button {
                            showRegenerateConfirmation = true
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .alert("Regenerate Secret?", isPresented: $showRegenerateConfirmation) {
                    Button("Regenerate", role: .destructive) {
                        viewModel.regenerateWebhookSecret()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your webhook endpoint will need to be updated with the new secret to continue accepting requests.")
                }
            }
        } header: {
            Text("Webhook")
        } footer: {
            if viewModel.webhookEnabled {
                Text("Each transcription is POSTed to your HTTPS endpoint with an HMAC-SHA256 signature in the X-Webhook-Signature header. Verify the signature using your secret to confirm authenticity.")
            } else {
                Text("Send your transcriptions to another service automatically. Connect Ramble to an AI agent, a cloud workflow, or any custom automation that processes your voice notes.")
            }
        }
    }

    private var statsSection: some View {
        Section("Statistics") {
            HStack {
                Text("Total Recordings")
                Spacer()
                Text("\(viewModel.totalRecordings)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Total Duration")
                Spacer()
                Text(formatTotalDuration(viewModel.totalDuration))
                    .foregroundStyle(.secondary)
            }

            if viewModel.pendingTranscriptions > 0 {
                HStack {
                    Text("Pending Transcriptions")
                    Spacer()
                    Text("\(viewModel.pendingTranscriptions)")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.failedTranscriptions > 0 {
                HStack {
                    Text("Failed Transcriptions")
                    Spacer()
                    Text("\(viewModel.failedTranscriptions)")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var exportSection: some View {
        Section("Data") {
            Button("Export All Recordings (JSON)") {
                if let url = viewModel.exportJSON() {
                    exportURL = url
                    showExportShare = true
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        Section("Danger Zone") {
            Button("Delete All Data", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all recordings and transcriptions.")
        }
    }

    private func formatTotalDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ProviderRowView: View {
    let provider: TranscriptionProvider
    let isSelected: Bool
    var isPremiumLocked: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: provider.iconName)
                    .font(.title3)
                    .foregroundStyle(provider.isCloud ? .blue : .green)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(provider.isCloud
                                ? Color.blue.opacity(0.12)
                                : Color.green.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if isPremiumLocked {
                            Text("PRO")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.blue)
                                )
                        }
                    }
                    Text(provider.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if isPremiumLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
