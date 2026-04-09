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
    @State private var showSecretRevealed = false
    @State private var showTranscriptionInfo = false
    @State private var showWebhookInfo = false
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
            .sheet(isPresented: $showTranscriptionInfo) {
                TranscriptionInfoSheet()
            }
            .sheet(isPresented: $showWebhookInfo) {
                WebhookInfoSheet()
            }
        }
    }

    private var transcriptionSection: some View {
        let isPremium = SubscriptionService.shared.isPremium

        return Section {
            // Apple Speech — always available
            ProviderRowView(
                provider: .appleSpeech,
                isSelected: viewModel.transcriptionProvider == .appleSpeech,
                onSelect: { viewModel.transcriptionProvider = .appleSpeech }
            )

            // Each cloud model shown individually
            ForEach(CloudModel.allCases) { model in
                CloudModelRowView(
                    model: model,
                    isSelected: viewModel.transcriptionProvider == .cloudTranscription
                        && viewModel.cloudModel == model,
                    isPremiumLocked: !isPremium,
                    onSelect: { viewModel.selectCloudModel(model) }
                )
            }
        } header: {
            HStack {
                Text("Transcription")
                Spacer()
                Button {
                    showTranscriptionInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .textCase(.none)
                }
            }
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
                    HStack {
                        Text("Signing Secret")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            withAnimation { showSecretRevealed.toggle() }
                        } label: {
                            Image(systemName: showSecretRevealed ? "eye.slash" : "eye")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if showSecretRevealed {
                        Text(viewModel.webhookSecret)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = viewModel.webhookSecret
                            showSecretCopied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                showSecretCopied = false
                            }
                        } label: {
                            Label("Copy", systemImage: showSecretCopied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(showSecretCopied ? .green : nil)

                        Button {
                            showRegenerateConfirmation = true
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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

            Button {
                showWebhookInfo = true
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Webhook setup guide")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Webhook")
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

struct CloudModelRowView: View {
    let model: CloudModel
    let isSelected: Bool
    var isPremiumLocked: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(model.iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(model.subtitle)
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

struct TranscriptionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Accurately turn your voice into text. Pick a provider.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    InfoBlock(
                        icon: "iphone",
                        title: "Apple Speech",
                        text: "On-device transcription that never leaves your phone. Free, private, no network required. iOS 26 brings a significantly improved speech model with better accuracy out of the box."
                    )

                    InfoBlock(
                        icon: "cloud",
                        title: "Why cloud?",
                        text: "Cloud models are more accurate — especially in noisy environments, with accents, or when speaking quickly. They also produce better punctuation, capitalization, and number formatting. Worth it if you rely on clean transcripts."
                    )

                    InfoBlock(
                        icon: "lock.shield",
                        title: "Cloud models are private too",
                        text: "Cloud transcription routes through our open-source proxy. No audio or text is stored on our servers — your audio goes to the provider and the transcript comes back. That's it."
                    )

                    InfoBlock(
                        icon: "eye",
                        title: "Don't take our word for it",
                        text: "Ramble is fully open source. Check the code on GitHub — no accounts, no user data stored. Your audio and transcriptions never touch our servers."
                    )
                }
                .padding()
            }
            .navigationTitle("About Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct WebhookInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Automatically send your transcripts somewhere useful.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    InfoBlock(
                        icon: "paperplane",
                        title: "How it works",
                        text: "Each transcription is POSTed as JSON to your URL. Requests are signed with your secret and retried automatically if your endpoint is down."
                    )

                    InfoBlock(
                        icon: "cpu",
                        title: "Connect to anything",
                        text: "Pipe transcripts into an AI agent, a Zapier workflow, a Notion database, or your own backend. Any HTTPS endpoint that accepts JSON works."
                    )

                    Link(destination: URL(string: "https://github.com/Jpoliachik/ramble-ios/blob/main/docs/webhook-api.md")!) {
                        HStack {
                            Spacer()
                            Label("View Full API Docs", systemImage: "doc.text")
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Webhook Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct InfoBlock: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
