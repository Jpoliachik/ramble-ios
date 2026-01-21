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
    @State private var exportURL: URL?

    var body: some View {
        NavigationView {
            Form {
                statsSection
                webhookSection
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
            HStack {
                Text("Estimated Cost")
                Spacer()
                Text(String(format: "$%.2f", viewModel.estimatedCost))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var webhookSection: some View {
        Section {
            TextField("https://example.com/webhook", text: $viewModel.webhookURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            VStack(alignment: .leading, spacing: 8) {
                Text("Auth Token")
                HStack {
                    Text(viewModel.webhookAuthToken)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        HapticService.buttonTap()
                        UIPasteboard.general.string = viewModel.webhookAuthToken
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                }
            }

            Button("Regenerate Token") {
                HapticService.buttonTap()
                viewModel.regenerateAuthToken()
            }
        } header: {
            Text("Webhook")
        } footer: {
            Text("Completed transcriptions will be POSTed to this URL with the auth token in the Authorization header.")
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
