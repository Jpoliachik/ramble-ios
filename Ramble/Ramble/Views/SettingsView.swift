//
//  SettingsView.swift
//  Ramble
//

import SwiftUI

private enum SettingsLinks {
    static let privacy = URL(string: "https://ramble.watch/privacy")!
    static let terms = URL(string: "https://ramble.watch/terms")!
    static let docs = URL(string: "https://ramble.watch/docs")!
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var relay = RelayService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showDestinationEdit = false
    @State private var showPrivacyInfo = false
    @State private var versionTapCount = 0
    @State private var showDebugSheet = false
    @State private var showConnectAgent = false
    @State private var watchState: WatchInstallState = .checking

    var body: some View {
        NavigationStack {
            Form {
                destinationsSection
                watchSection
                transcriptionSection
                appSection
                aboutSection
            }
            .listSectionSpacing(24)
            .tint(Color.brandAmber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.save()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDebugSheet) {
                DebugSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showPrivacyInfo) {
                PrivacyInfoSheet()
            }
            .sheet(isPresented: $showDestinationEdit) {
                WebhookDestinationEditSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showConnectAgent) {
                ConnectAgentView()
            }
            .task {
                watchState = WatchInstallState.current()
                guard relay.hasInbox else { return }
                _ = try? await relay.refreshConnections()
            }
        }
    }

    // MARK: - Where notes go

    private var destinationsSection: some View {
        Section {
            Button {
                HapticService.buttonTap()
                showConnectAgent = true
            } label: {
                SettingsRow(
                    icon: "sparkles",
                    iconTint: .brandAmber,
                    title: "Your agent",
                    subtitle: agentSubtitle,
                    dot: agentDot
                ) {
                    chevron
                }
            }
            .buttonStyle(.plain)

            Button {
                HapticService.buttonTap()
                showDestinationEdit = true
            } label: {
                SettingsRow(
                    icon: "link",
                    title: "Webhook",
                    subtitle: viewModel.webhookURL.isEmpty ? "Off" : destinationHost,
                    dot: viewModel.webhookURL.isEmpty ? nil : webhookDot
                ) {
                    if viewModel.webhookURL.isEmpty {
                        Text("Add")
                            .foregroundStyle(Color.obInkFaint)
                    }
                    chevron
                }
            }
            .buttonStyle(.plain)
        } header: {
            SettingsGroupTitle(title: "Where notes go")
        }
    }

    /// Same words and dot colors as the Home status line.
    private var agentSubtitle: String {
        guard let connection = primaryConnection else {
            return relay.hasConnectedAgents ? "Connected" : "Not connected"
        }
        if AgentHealth(connection) == .quiet, let last = connection.lastPullAt {
            return "Hasn't checked in · \(HomeStatusLine.age(since: last))"
        }
        return AgentHealth.summary(connection)
    }

    private var agentDot: Color {
        guard relay.hasConnectedAgents else { return Color(.tertiaryLabel) }
        if let connection = primaryConnection, AgentHealth(connection) == .quiet { return .brandAmber }
        return .green
    }

    /// The connection most worth describing: a quiet one first, then the
    /// one that checked in most recently.
    private var primaryConnection: RelayConnection? {
        relay.connections.first { AgentHealth($0) == .quiet }
            ?? relay.connections.max { ($0.lastPullAt ?? .distantPast) < ($1.lastPullAt ?? .distantPast) }
    }

    private var webhookDot: Color {
        switch viewModel.webhookHealth {
        case .healthy: return .green
        case .error: return .red
        case .untested: return Color(.tertiaryLabel)
        }
    }

    private var destinationHost: String {
        URL(string: viewModel.webhookURL)?.host ?? viewModel.webhookURL
    }

    // MARK: - Watch

    private var watchSection: some View {
        Section {
            Button {
                guard watchState == .notInstalled, let url = URL(string: "itms-watchs://") else { return }
                HapticService.buttonTap()
                openURL(url)
            } label: {
                HStack(spacing: 12) {
                    Image("ramble-app-icon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ramble on Apple Watch")
                            .foregroundStyle(Color.obInk)
                        Text(watchSubtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.obInkFaint)
                    }
                    Spacer()
                    switch watchState {
                    case .installed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    case .notInstalled:
                        Text("Install")
                            .foregroundStyle(Color.brandAmber)
                        chevron
                    case .checking, .noWatch:
                        EmptyView()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            SettingsGroupTitle(title: "Watch")
        }
    }

    private var watchSubtitle: String {
        switch watchState {
        case .checking: return "Checking…"
        case .installed: return "Installed"
        case .notInstalled: return "Not installed yet. Install it from the Watch app."
        case .noWatch: return "No Apple Watch paired. You can record on iPhone."
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        Section {
            NavigationLink {
                TranscriptionSettingsView(viewModel: viewModel)
            } label: {
                SettingsRow(
                    icon: "waveform",
                    title: "Model",
                    subtitle: modelSubtitle
                ) {
                    EmptyView()
                }
            }
        } header: {
            SettingsGroupTitle(title: "Transcription")
        }
    }

    private var modelSubtitle: String {
        if viewModel.transcriptionProvider.isCloud {
            return "Cloud · \(viewModel.cloudModel.displayName)"
        }
        return "On-device · free"
    }

    // MARK: - App

    private var appSection: some View {
        Section {
            Picker(selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            } label: {
                SettingsRow(icon: "moon", title: "Appearance") { EmptyView() }
            }
            .pickerStyle(.menu)

            Button {
                HapticService.buttonTap()
                showPrivacyInfo = true
            } label: {
                SettingsRow(icon: "lock", title: "How privacy works") { chevron }
            }
            .buttonStyle(.plain)

            NavigationLink {
                YourDataView(viewModel: viewModel)
            } label: {
                SettingsRow(
                    icon: "shippingbox",
                    title: "Your data",
                    subtitle: "\(viewModel.totalRecordings) \(viewModel.totalRecordings == 1 ? "note" : "notes") · \(formatTotalDuration(viewModel.totalDuration))"
                ) {
                    EmptyView()
                }
            }
        } header: {
            SettingsGroupTitle(title: "App")
        }
    }

    private var aboutSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return Section {
            VStack(spacing: 8) {
                Text("Ramble \(version) (\(build))")
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
                    Link("Privacy Policy", destination: SettingsLinks.privacy)
                    Link("Terms of Use", destination: SettingsLinks.terms)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    /// Matches the system NavigationLink chevron on the other rows.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(.tertiaryLabel))
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

/// A settings row: rounded icon tile, title, optional subtitle with a status
/// dot, and a trailing slot.
private struct SettingsRow<Trailing: View>: View {
    let icon: String
    var iconTint: Color = Color.obInkSoft
    let title: String
    var subtitle: String? = nil
    var dot: Color? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 30, height: 30)
                .background(
                    iconTint == .brandAmber ? Color.brandAmberSoft : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.obInk)
                if let subtitle {
                    HStack(spacing: 6) {
                        if let dot {
                            Circle().fill(dot).frame(width: 7, height: 7)
                        }
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.obInkFaint)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Transcription model page

/// The model picker, cloud upgrade and cloud tuning, one level down so
/// people who never change the model never see the price list.
private struct TranscriptionSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showTranscriptionInfo = false

    private var isSpeechAnalyzerAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        Form {
            freeSection
            cloudSection
            tuningSection
        }
        .listSectionSpacing(24)
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showTranscriptionInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About transcription")
            }
        }
        .sheet(isPresented: $showTranscriptionInfo) {
            TranscriptionInfoSheet()
        }
        .sheet(isPresented: $viewModel.showSubscriptionPaywall) {
            SubscriptionView()
        }
        .onDisappear { viewModel.save() }
    }

    private var freeSection: some View {
        Section {
            BrandCard {
                AppleSpeechRow(
                    isSelected: viewModel.transcriptionProvider == .appleSpeech,
                    onTap: { viewModel.transcriptionProvider = .appleSpeech }
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)

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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            SettingsSubsectionLabel("Free · on-device")
        }
    }

    private var cloudSection: some View {
        Section {
            BrandCard {
                ForEach(Array(CloudModel.allCases.enumerated()), id: \.element.id) { index, model in
                    CloudModelRow(
                        model: model,
                        isSelected: viewModel.transcriptionProvider == .cloudTranscription
                            && viewModel.cloudModel == model,
                        isLocked: !subscriptionService.isPremium,
                        onTap: { viewModel.selectCloudModel(model) }
                    )

                    if index < CloudModel.allCases.count - 1 {
                        BrandRowDivider()
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
        } header: {
            if subscriptionService.isPremium {
                SettingsSubsectionLabel("Cloud · premium")
            } else {
                SettingsSubsectionLabel(title: "Cloud · premium") {
                    Text("$2.99 / month")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
        } footer: {
            Text("Cloud transcription sends audio through our proxy to the provider. The proxy doesn't keep the audio or the text.")
        }
    }

    private var tuningSection: some View {
        // Shown always: on Apple Speech it renders as a locked teaser so
        // the person can see what cloud unlocks.
        let isCloud = viewModel.transcriptionProvider.isCloud
        return Section {
            NavigationLink {
                LanguagePickerView(
                    selection: $viewModel.transcriptionLanguage,
                    supported: viewModel.cloudModel.supportedLanguages
                )
            } label: {
                HStack {
                    Text("Language")
                    Spacer()
                    Text(viewModel.transcriptionLanguage.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "e.g. Goodloop, Ramble, Cloudflare Workers",
                    text: $viewModel.customVocabulary,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                Text("Names, jargon, and phrases the model might miss. Comma-separated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Remove filler words", isOn: $viewModel.removeFillerWords)
        } header: {
            SettingsSubsectionLabel(title: "Cloud · tuning") {
                if !isCloud {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
        }
        .disabled(!isCloud)
        .opacity(isCloud ? 1 : 0.5)
    }
}

// MARK: - Your data

/// Stats, export and "Delete all data", kept off the main Settings screen
/// so nothing destructive sits there.
private struct YourDataView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes", value: "\(viewModel.totalRecordings)")
                LabeledContent("Total length", value: formatTotalDuration(viewModel.totalDuration))
                if viewModel.pendingTranscriptions > 0 {
                    LabeledContent("Waiting to transcribe", value: "\(viewModel.pendingTranscriptions)")
                }
                if viewModel.failedTranscriptions > 0 {
                    LabeledContent("Couldn't transcribe", value: "\(viewModel.failedTranscriptions)")
                }
            }

            Section {
                Button {
                    if let url = viewModel.exportJSON() {
                        exportURL = url
                        showExportShare = true
                    }
                } label: {
                    Label("Export all notes (JSON)", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.obInk)
                }
            } footer: {
                Text("Transcripts and details for every note, as one JSON file.")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete all data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
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
}

struct TranscriptionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 16) {
                        OnboardingIllustration(name: "illustration-transcribe")
                        OnboardingHeadline(size: 28) {
                            Text("Voice in, ") + Text("text out.").italic()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

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
                        text: "Cloud transcription sends your audio through our proxy to the provider, and the transcript comes back. The proxy doesn't keep the audio or the text."
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
                        icon: "applewatch",
                        title: "Recorded on your devices",
                        text: "Recordings from your watch and phone are saved on your phone. Audio isn't uploaded anywhere unless you pick a cloud model."
                    )

                    InfoBlock(
                        icon: "lock.shield",
                        title: "On-device transcription stays put",
                        text: "Apple Speech transcribes audio entirely on your iPhone — nothing leaves the device. It's the default."
                    )

                    InfoBlock(
                        icon: "cloud",
                        title: "Cloud transcription is opt-in",
                        text: "If you choose a cloud model, audio is sent through our proxy to the provider, transcribed, and the text comes back. The proxy doesn't keep the audio or the transcript."
                    )

                    InfoBlock(
                        icon: "tray.and.arrow.up",
                        title: "Your agent's inbox is temporary",
                        text: "When you connect an agent, transcripts wait on the Ramble relay until it picks them up. The text is deleted the moment it does. Anything never picked up is deleted after \(Constants.Relay.unclaimedRetentionDays) days. Audio never goes there. No accounts."
                    )

                    InfoBlock(
                        icon: "paperplane",
                        title: "Webhooks go where you point them",
                        text: "If you configure a webhook, transcripts are POSTed straight from your phone to a URL you control. Nothing is kept on our side."
                    )

                    Link(destination: SettingsLinks.privacy) {
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
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 16) {
                        OnboardingIllustration(name: "illustration-automate")
                        OnboardingHeadline(size: 28) {
                            Text("Send it ") + Text("anywhere you point.").italic()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    InfoBlock(
                        icon: "paperplane",
                        title: "How it works",
                        text: "Each transcription is POSTed as JSON to your URL. Requests are signed with your secret and retried automatically if your endpoint is down."
                    )

                    InfoBlock(
                        icon: "cpu",
                        title: "Connect to anything",
                        text: "Pipe transcripts into a Zapier workflow, a Notion database, or your own backend. Any HTTPS endpoint that accepts JSON works. To send them to your agent, use Connect your agent instead."
                    )

                    Link(destination: SettingsLinks.docs) {
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
                .foregroundStyle(Color.brandAmber)
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
    @AppStorage(Constants.Relay.baseURLOverrideKey) private var relayBaseURLOverride = ""
    @State private var isReattesting = false
    @State private var fastDeliveryAlerts = DeliveryMonitor.isFastMode

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Fast stuck-note alerts", isOn: $fastDeliveryAlerts)
                        .onChange(of: fastDeliveryAlerts) { _, enabled in
                            DeliveryMonitor.isFastMode = enabled
                            DeliveryMonitor.shared.evaluate()
                        }
                } header: {
                    Text("Delivery alerts")
                } footer: {
                    Text("Thresholds drop from hours to seconds (30s stuck on phone, 5s needs you, 60s not picked up, 60s on the watch) and the cooldown to a minute. Also sent to the watch.")
                }

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

                Section {
                    HStack {
                        TextField("https://relay.example.com", text: $relayBaseURLOverride)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !relayBaseURLOverride.isEmpty {
                            Button {
                                relayBaseURLOverride = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Relay")
                } footer: {
                    Text("Point at a `wrangler dev` relay, e.g. http://localhost:8787. Leave empty for the built-in relay. The server bypass key above is sent as the relay's X-Dev-Bypass header.")
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

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _draftURL = State(initialValue: viewModel.webhookURL)
        let secret = viewModel.webhookSecret.isEmpty ? Settings.generateSecret() : viewModel.webhookSecret
        _draftSecret = State(initialValue: secret)
    }

    private var trimmedURL: String {
        draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        WebhookDestinationEditor(
            draftURL: $draftURL,
            draftSecret: $draftSecret,
            draftURLError: $draftURLError,
            isEditing: !viewModel.webhookURL.isEmpty,
            canSave: !trimmedURL.isEmpty && draftURLError == nil,
            onSave: save,
            onCancel: { dismiss() },
            onValidateURL: validateURL,
            onRegenerate: { draftSecret = Settings.generateSecret() },
            onRemove: remove
        )
    }

    private func validateURL() {
        if trimmedURL.isEmpty {
            draftURLError = nil
            return
        }
        draftURLError = WebhookQueueService.validateWebhookURL(trimmedURL)
    }

    private func save() {
        viewModel.webhookURL = trimmedURL
        viewModel.webhookSecret = draftSecret
        viewModel.save()
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

// MARK: - Settings header components

/// Serif group title — top-level grouping label (Destinations, Transcribe).
/// Mirrors the onboarding headline aesthetic at a smaller size, with an
/// optional friendly subtitle below.
private struct SettingsGroupTitle<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, design: .serif).weight(.medium))
                    .tracking(-0.3)
                    .foregroundStyle(Color.obInk)
                Spacer(minLength: 0)
                trailing()
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.obInkSoft)
            }
        }
        .textCase(.none)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

extension SettingsGroupTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// Uppercase tracked subsection label — matches `OnboardingSectionHeader` style.
/// Optional trailing slot for prices, info buttons, etc.
private struct SettingsSubsectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Color.obInkFaint)
            Spacer()
            trailing()
        }
        .textCase(.none)
    }
}

extension SettingsSubsectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

/// Language picker — only shows the languages supported by the currently
/// selected transcription path (provider + model). The caller is responsible
/// for resetting `selection` to `.auto` if the user switches to a path that
/// doesn't support their previously chosen language.
struct LanguagePickerView: View {
    @Binding var selection: TranscriptionLanguage
    let supported: Set<TranscriptionLanguage>
    @Environment(\.dismiss) private var dismiss

    private var visibleLanguages: [TranscriptionLanguage] {
        let rest = TranscriptionLanguage.sortedCases
            .filter { $0 != .auto && supported.contains($0) }
        return [.auto] + rest
    }

    var body: some View {
        List {
            ForEach(visibleLanguages) { language in
                Button {
                    selection = language
                    dismiss()
                } label: {
                    HStack {
                        Text(language.displayName)
                            .foregroundStyle(Color.obInk)
                        Spacer()
                        if selection == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandAmber)
                        }
                    }
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
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
