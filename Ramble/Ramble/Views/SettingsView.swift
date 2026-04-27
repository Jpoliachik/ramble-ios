//
//  SettingsView.swift
//  Ramble
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showExportShare = false
    @State private var showTranscriptionInfo = false
    @State private var showWebhookInfo = false
    @State private var showDestinationEdit = false
    @State private var exportURL: URL?
    @State private var versionTapCount = 0
    @State private var showDebugSheet = false

    var body: some View {
        NavigationView {
            Form {
                transcriptionSection
                webhookSection
                appearanceSection
                statsSection
                exportSection
                dangerZoneSection
                aboutSection
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
            .sheet(isPresented: $showDebugSheet) {
                DebugSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showTranscriptionInfo) {
                TranscriptionInfoSheet()
            }
            .sheet(isPresented: $showWebhookInfo) {
                WebhookInfoSheet()
            }
            .sheet(isPresented: $showDestinationEdit) {
                WebhookDestinationEditSheet(viewModel: viewModel)
            }
        }
    }

    private var isSpeechAnalyzerAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private var appleSpeechSubtitle: String {
        isSpeechAnalyzerAvailable ? "Built into iOS · works offline" : "Free, on-device"
    }

    private var transcriptionSection: some View {
        Section {
            TranscriptionModelRow(
                title: TranscriptionProvider.appleSpeech.displayName,
                subtitle: appleSpeechSubtitle,
                logo: .system(TranscriptionProvider.appleSpeech.iconName),
                isSelected: viewModel.transcriptionProvider == .appleSpeech,
                onTap: { viewModel.transcriptionProvider = .appleSpeech }
            )
            .listRowInsets(EdgeInsets())

            if !isSpeechAnalyzerAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text("Update to iOS 26 for a significantly improved speech model with better accuracy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(CloudModel.allCases) { model in
                TranscriptionModelRow(
                    title: model.displayName,
                    subtitle: model.subtitle,
                    logo: .asset(model.iconName),
                    isSelected: viewModel.transcriptionProvider == .cloudTranscription
                        && viewModel.cloudModel == model,
                    isLocked: !subscriptionService.isPremium,
                    showsRecommended: model == .whisperLargeV3Turbo,
                    onTap: { viewModel.selectCloudModel(model) }
                )
                .listRowInsets(EdgeInsets())
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
            if viewModel.webhookURL.isEmpty {
                Button {
                    showDestinationEdit = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        Text("Add destination")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            } else {
                Button {
                    showDestinationEdit = true
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destinationHost)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("Transcripts are sent automatically")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
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

    private var destinationHost: String {
        URL(string: viewModel.webhookURL)?.host ?? viewModel.webhookURL
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
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

    private var aboutSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return Section {
            VStack(spacing: 8) {
                Text("Ramble v\(version) (\(build))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 4 {
                            versionTapCount = 0
                            showDebugSheet = true
                        }
                    }

                HStack(spacing: 16) {
                    Link("Privacy Policy", destination: URL(string: "https://goodloop.dev/ramble/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://goodloop.dev/ramble/terms")!)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
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

                    Link(destination: URL(string: "https://github.com/Jpoliachik/ramble-ios")!) {
                        HStack {
                            Spacer()
                            Label("View Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
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

struct PrivacyInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your audio belongs to you. Here's exactly where it goes — and where it doesn't.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    InfoBlock(
                        icon: "iphone",
                        title: "Recorded on your device",
                        text: "Recordings are saved locally to your phone. They aren't uploaded anywhere automatically."
                    )

                    InfoBlock(
                        icon: "lock.shield",
                        title: "On-device transcription stays put",
                        text: "Apple Speech transcribes audio entirely on your iPhone — nothing leaves the device. It's the default."
                    )

                    InfoBlock(
                        icon: "cloud",
                        title: "Cloud transcription is opt-in",
                        text: "If you choose a cloud model, audio is sent through our open-source proxy to the provider, transcribed, and the text comes back. We don't store the audio or the transcript."
                    )

                    InfoBlock(
                        icon: "paperplane",
                        title: "Webhooks go where you point them",
                        text: "If you configure a webhook, transcripts are POSTed to a URL you control. That's the only place transcripts ever leave your device — and only when you set it up."
                    )

                    InfoBlock(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "Open source",
                        text: "Ramble is open source. Read the code, audit the proxy, run your own. No accounts, no analytics."
                    )

                    Link(destination: URL(string: "https://goodloop.dev/ramble/privacy")!) {
                        HStack {
                            Spacer()
                            Label("Read the full privacy policy", systemImage: "doc.text")
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("How privacy works")
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

                    Link(destination: URL(string: "https://goodloop.dev/ramble/docs")!) {
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

struct DebugSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SettingsViewModel
    @State private var attestStatus = ""
    @State private var isReattesting = false

    var body: some View {
        NavigationView {
            Form {
                Section("Developer Override") {
                    HStack {
                        TextField("Server bypass key", text: $viewModel.devOverrideKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !viewModel.devOverrideKey.isEmpty {
                            Button {
                                viewModel.devOverrideKey = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("App Attest") {
                    HStack {
                        Text("Supported")
                        Spacer()
                        Text(AppAttestService.shared.isSupported ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Attested")
                        Spacer()
                        Text(AppAttestService.shared.isAttested ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                    if let keyId = AppAttestService.shared.keyId {
                        HStack {
                            Text("Key ID")
                            Spacer()
                            Text(String(keyId.prefix(12)) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        isReattesting = true
                        attestStatus = ""
                        Task {
                            AppAttestService.shared.resetState()
                            do {
                                try await AppAttestService.shared.attestIfNeeded()
                                attestStatus = "Re-attestation succeeded"
                            } catch {
                                attestStatus = "Failed: \(error.localizedDescription)"
                            }
                            isReattesting = false
                        }
                    } label: {
                        HStack {
                            if isReattesting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Re-attesting...")
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("Reset & Re-attest")
                            }
                        }
                    }
                    .disabled(isReattesting)

                    if !attestStatus.isEmpty {
                        Text(attestStatus)
                            .font(.caption)
                            .foregroundStyle(attestStatus.contains("succeeded") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WebhookDestinationEditSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftURL: String
    @State private var draftSecret: String
    @State private var draftURLError: String?
    @State private var showRegenerateConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var showSecretRevealed = false
    @State private var showSecretCopied = false

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _draftURL = State(initialValue: viewModel.webhookURL)
        let secret = viewModel.webhookSecret.isEmpty ? Settings.generateSecret() : viewModel.webhookSecret
        _draftSecret = State(initialValue: secret)
    }

    private var isEditing: Bool {
        !viewModel.webhookURL.isEmpty
    }

    private var trimmedURL: String {
        draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedURL.isEmpty && draftURLError == nil
    }

    private var isTestLoading: Bool {
        if case .loading = viewModel.testWebhookResult { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                urlSection
                secretSection
                if canSave {
                    testSection
                }
                if isEditing {
                    removeSection
                }
            }
            .navigationTitle(isEditing ? "Edit destination" : "Add destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Regenerate secret?",
                isPresented: $showRegenerateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Regenerate", role: .destructive) {
                    draftSecret = Settings.generateSecret()
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
                Button("Remove", role: .destructive) {
                    remove()
                }
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
                .onChange(of: draftURL) { validateURL() }
            if let error = draftURLError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("URL")
        } footer: {
            Text("Ramble will POST each transcript as JSON to this URL.")
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
            Text("Use this to verify requests on your endpoint.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                persistDraft()
                viewModel.sendTestWebhook()
            } label: {
                HStack {
                    switch viewModel.testWebhookResult {
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

    private func validateURL() {
        if trimmedURL.isEmpty {
            draftURLError = nil
            return
        }
        draftURLError = WebhookQueueService.validateWebhookURL(trimmedURL)
    }

    // Pushes draft values into the view model and persists. Used by Save and Test.
    private func persistDraft() {
        viewModel.webhookURL = trimmedURL
        viewModel.webhookSecret = draftSecret
        viewModel.save()
    }

    private func save() {
        persistDraft()
        HapticService.success()
        dismiss()
    }

    private func remove() {
        viewModel.webhookURL = ""
        viewModel.save()
        HapticService.success()
        dismiss()
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
