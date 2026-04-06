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
        }
    }

    private var transcriptionSection: some View {
        Section {
            ForEach(TranscriptionProvider.allCases) { provider in
                ProviderRowView(
                    provider: provider,
                    isSelected: viewModel.transcriptionProvider == provider,
                    onSelect: { viewModel.transcriptionProvider = provider }
                )
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
                        .foregroundColor(.secondary)
                    TextField("https://your-webhook.example.com", text: $viewModel.webhookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Secret")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(viewModel.webhookSecret)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = viewModel.webhookSecret
                            showSecretCopied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                showSecretCopied = false
                            }
                        } label: {
                            Label(showSecretCopied ? "Copied" : "Copy", systemImage: showSecretCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            viewModel.regenerateWebhookSecret()
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Webhook")
        } footer: {
            if viewModel.webhookEnabled {
                Text("Each time a transcription completes, Ramble POSTs the text to your URL with an X-Webhook-Secret header. Use the secret to verify requests came from your device.")
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
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Total Duration")
                Spacer()
                Text(formatTotalDuration(viewModel.totalDuration))
                    .foregroundColor(.secondary)
            }

            if viewModel.pendingTranscriptions > 0 {
                HStack {
                    Text("Pending Transcriptions")
                    Spacer()
                    Text("\(viewModel.pendingTranscriptions)")
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.failedTranscriptions > 0 {
                HStack {
                    Text("Failed Transcriptions")
                    Spacer()
                    Text("\(viewModel.failedTranscriptions)")
                        .foregroundColor(.red)
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
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
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
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: provider.iconName)
                    .font(.title3)
                    .foregroundColor(provider.isCloud ? .blue : .green)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(provider.isCloud
                                ? Color.blue.opacity(0.12)
                                : Color.green.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(provider.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.accentColor)
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
