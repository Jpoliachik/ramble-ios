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
                connectionSection
                statsSection
                apiSection
                exportSection
                dangerZoneSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !viewModel.apiBaseURL.isEmpty {
                    Task { await viewModel.testConnection() }
                }
            }
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

    private var connectionSection: some View {
        Section("Connection") {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 10, height: 10)
                Text(connectionLabel)
                Spacer()
            }

            if viewModel.pendingUploads > 0 {
                HStack {
                    Text("Pending Uploads")
                    Spacer()
                    Text("\(viewModel.pendingUploads)")
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.failedUploads > 0 {
                HStack {
                    Text("Failed Uploads")
                    Spacer()
                    Text("\(viewModel.failedUploads)")
                        .foregroundColor(.red)
                }
            }

            Button {
                Task { await viewModel.testConnection() }
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    if viewModel.isTesting {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.apiBaseURL.isEmpty || viewModel.isTesting)
        }
    }

    private var connectionDotColor: Color {
        guard let status = viewModel.connectionStatus else { return .gray }
        switch status {
        case .success: return .green
        case .notConfigured: return .gray
        case .unauthorized, .networkError, .serverError: return .red
        }
    }

    private var connectionLabel: String {
        guard let status = viewModel.connectionStatus else { return "Not tested" }
        switch status {
        case .success: return "Connected"
        case .notConfigured: return "Not configured"
        case .unauthorized: return "Unauthorized — check token"
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let code, _): return "Server error (\(code))"
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
        }
    }

    private var apiSection: some View {
        Section {
            TextField("https://example.com", text: $viewModel.apiBaseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Bearer token", text: $viewModel.apiToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
        } header: {
            Text("Ramble API")
        } footer: {
            Text("Enter your backend URL and auth token. Recordings upload to <base>/ramble/recordings for transcription and processing.")
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
