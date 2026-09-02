//
//  SettingsView.swift
//  Ramble
//

import SwiftUI

private enum SettingsLinks {
    static let privacy = URL(string: "https://goodloop.dev/ramble/privacy")!
    static let terms = URL(string: "https://goodloop.dev/ramble/terms")!
    static let docs = URL(string: "https://goodloop.dev/ramble/docs")!
    static let github = URL(string: "https://github.com/Jpoliachik/ramble-ios")!
}

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
                freeTranscriptionSection
                cloudTranscriptionSection
                cloudTuningSection
                webhookSection
                appearanceSection
                statsSection
                exportSection
                dangerZoneSection
                aboutSection
            }
            .listSectionSpacing(28)
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

    private var freeTranscriptionSection: some View {
        Section {
            BrandCard {
                AppleSpeechRow(
                    isSelected: viewModel.transcriptionProvider == .appleSpeech,
                    onTap: { viewModel.transcriptionProvider = .appleSpeech }
                )
                ForEach(LocalWhisperModel.allCases) { model in
                    BrandRowDivider()
                    LocalWhisperRow(
                        model: model,
                        isSelected: viewModel.transcriptionProvider == .localWhisper
                            && viewModel.localWhisperModel == model,
                        onTap: {
                            viewModel.transcriptionProvider = .localWhisper
                            viewModel.localWhisperModel = model
                        }
                    )
                }
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
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroupTitle(
                    title: "Transcribe",
                    subtitle: "How your voice becomes text."
                ) {
                    Button {
                        showTranscriptionInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                    }
                }
                SettingsSubsectionLabel("Free · on-device")
            }
            .textCase(.none)
        }
    }

    private var cloudTranscriptionSection: some View {
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
                    Text("$3.99 / month")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
        } footer: {
            Text("Cloud transcription routes through our open-source proxy. No audio or text is stored on our servers.")
        }
    }

    private var cloudTuningSection: some View {
        // Shown always — on Apple Speech the section renders as a locked teaser so
        // the user can see what the other models unlock. Local Whisper takes both
        // a language hint and the vocabulary, so it gets the section unlocked too.
        let isTunable = viewModel.transcriptionProvider.isCloud
            || viewModel.transcriptionProvider == .localWhisper
        let supportedLanguages: Set<TranscriptionLanguage> = viewModel.transcriptionProvider == .localWhisper
            ? Set(TranscriptionLanguage.allCases.filter { $0 != .auto })
            : viewModel.cloudModel.supportedLanguages
        return Section {
            NavigationLink {
                LanguagePickerView(
                    selection: $viewModel.transcriptionLanguage,
                    supported: supportedLanguages
                )
            } label: {
                HStack {
                    Text("Main language")
                    Spacer()
                    Text(viewModel.transcriptionLanguage.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.transcriptionProvider == .localWhisper {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Multiple languages", isOn: $viewModel.useAdditionalLanguages)
                    Text("Transcribe meetings that use more than one language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.useAdditionalLanguages {
                    // No label: the toggle above already says what this is, the same
                    // way the dictionary's field needs no second heading.
                    NavigationLink {
                        SpokenLanguagesPickerView(selection: $viewModel.spokenLanguages)
                    } label: {
                        Text(spokenLanguagesSummary)
                            .foregroundStyle(
                                viewModel.spokenLanguages.isEmpty ? Color.secondary : Color.primary
                            )
                    }
                }
            }

            let isLocal = viewModel.transcriptionProvider == .localWhisper
            // On-device, the dictionary is applied by Apple Intelligence, so it
            // needs the model to be there.
            let dictionaryAvailable = viewModel.transcriptionProvider.isCloud
                || (isLocal && appleIntelligenceUnavailable == nil)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Dictionary", isOn: $viewModel.useDictionary)
                    .disabled(!dictionaryAvailable)
                Text(dictionaryDescription(isLocal: isLocal, available: dictionaryAvailable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(dictionaryAvailable ? 1 : 0.5)

            if dictionaryAvailable, viewModel.useDictionary {
                TextField(
                    "e.g. Goodloop, Ramble, Cloudflare Workers",
                    text: $viewModel.customVocabulary,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }

            Toggle("Remove filler words", isOn: $viewModel.removeFillerWords)

            if viewModel.transcriptionProvider == .localWhisper {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Identify speakers", isOn: $viewModel.identifySpeakers)
                    Text("Labels each speaker turn on-device. Downloads a small extra model the first time, and adds time to every transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }


            }
        } header: {
            SettingsSubsectionLabel(title: "Tuning") {
                if !isTunable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
        }
        .disabled(!isTunable)
        .opacity(isTunable ? 1 : 0.5)
    }

    private var webhookSection: some View {
        Section {
            if viewModel.webhookURL.isEmpty {
                BrandPlusActionCard(title: "Add a destination") {
                    showDestinationEdit = true
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            } else {
                Button {
                    showDestinationEdit = true
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(viewModel.webhookHealth.color)
                            .frame(width: 10, height: 10)
                            .accessibilityLabel(viewModel.webhookHealth.accessibilityLabel)
                        Text(destinationHost)
                            .font(.body)
                            .foregroundStyle(Color.obInk)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.obInkFaint)
                    }
                    .opacity(viewModel.webhookEnabled ? 1 : 0.4)
                }

                Toggle(isOn: $viewModel.webhookEnabled) {
                    Text(viewModel.webhookEnabled ? "Sending transcripts" : "Paused")
                        .font(.body)
                        .foregroundStyle(Color.obInk)
                }
                .tint(Color.brandRed)
                .onChange(of: viewModel.webhookEnabled) { _, _ in
                    HapticService.selection()
                    viewModel.save()
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroupTitle(
                    title: "Send via Webhook",
                    subtitle: "Pipe transcripts to any URL."
                ) {
                    Button {
                        showWebhookInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                    }
                }
                SendVisual(endpointText: SendVisual.endpointText(for: viewModel.webhookURL))
                    .padding(.bottom, 4)
                SettingsSubsectionLabel("Destination")
            }
            .textCase(.none)
        } footer: {
            Text("Create automations, send to an AI agent — anywhere that accepts an HTTPS POST. Make sure this is a trusted URL.")
        }
    }

    private var appleIntelligenceUnavailable: AppleIntelligenceService.Unavailable? {
        AppleIntelligenceService.unavailableReason()
    }

    private func dictionaryDescription(isLocal: Bool, available: Bool) -> String {
        if available {
            return isLocal
                ? "Names and jargon. Apple Intelligence corrects these on-device after transcribing."
                : "Names, jargon, and phrases the model might miss."
        }
        if isLocal, let reason = appleIntelligenceUnavailable {
            return "On-device, the dictionary is applied by Apple Intelligence, but \(reason.rawValue)."
        }
        return "Cloud models only."
    }

    private var spokenLanguagesSummary: String {
        let selected = viewModel.spokenLanguages.filter { $0 != .auto }
        // Reads as a placeholder when empty, like the dictionary's example text.
        guard !selected.isEmpty else { return "e.g. German, Spanish" }
        return selected.map(\.displayName).joined(separator: ", ")
    }

    private var destinationHost: String {
        URL(string: viewModel.webhookURL)?.host ?? viewModel.webhookURL
    }

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
        } header: {
            SettingsGroupTitle(title: "Appearance")
        }
    }

    private var statsSection: some View {
        Section {
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
        } header: {
            SettingsGroupTitle(title: "Statistics")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                if let url = viewModel.exportJSON() {
                    exportURL = url
                    showExportShare = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.obInk)
                        .frame(width: 22)
                    Text("Export all recordings (JSON)")
                        .foregroundStyle(Color.obInk)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
        } header: {
            SettingsGroupTitle(title: "Data")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.brandRed)
                        .frame(width: 22)
                    Text("Delete all data")
                        .foregroundStyle(Color.brandRed)
                    Spacer()
                }
            }
        } header: {
            SettingsGroupTitle(title: "Danger zone")
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
                    Link("Privacy Policy", destination: SettingsLinks.privacy)
                    Link("Terms of Use", destination: SettingsLinks.terms)
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
                        text: "Cloud transcription routes through our open-source proxy. No audio or text is stored on our servers — your audio goes to the provider and the transcript comes back. That's it."
                    )

                    InfoBlock(
                        icon: "eye",
                        title: "Don't take our word for it",
                        text: "Ramble is fully open source. Check the code on GitHub — no accounts, no user data stored. Your audio and transcriptions never touch our servers."
                    )

                    Link(destination: SettingsLinks.github) {
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
                        text: "Pipe transcripts into an AI agent, a Zapier workflow, a Notion database, or your own backend. Any HTTPS endpoint that accepts JSON works."
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
                .foregroundStyle(Color.brandRed)
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
    @State private var modelTestResult = ""
    @State private var isTestingModel = false

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

                Section("Apple Intelligence") {
                    HStack {
                        Text("Availability")
                        Spacer()
                        Text(AppleIntelligenceService.unavailableReason()?.rawValue ?? "Available")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button {
                        isTestingModel = true
                        Task {
                            modelTestResult = await AppleIntelligenceService.selfTest()
                            isTestingModel = false
                        }
                    } label: {
                        HStack {
                            Text(isTestingModel ? "Asking the model..." : "Run model test")
                            Spacer()
                            if isTestingModel { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTestingModel)

                    if !modelTestResult.isEmpty {
                        Text(modelTestResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

/// Serif group title — top-level grouping label (Transcribe, Send via Webhook).
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
/// Multi-select sibling of `LanguagePickerView`, for the languages actually
/// spoken. Order is selection order, which is also the decode order.
struct SpokenLanguagesPickerView: View {
    @Binding var selection: [TranscriptionLanguage]

    private var visibleLanguages: [TranscriptionLanguage] {
        TranscriptionLanguage.sortedCases.filter { $0 != .auto }
    }

    var body: some View {
        List {
            Section {
                ForEach(visibleLanguages) { language in
                    Button {
                        if let index = selection.firstIndex(of: language) {
                            selection.remove(at: index)
                        } else {
                            selection.append(language)
                        }
                        HapticService.selection()
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .foregroundStyle(Color.obInk)
                            Spacer()
                            if selection.contains(language) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandRed)
                            }
                        }
                    }
                }
            } footer: {
                Text("Only needed if a recording switches language part way through. Each language here adds a full transcription pass on top of the main language, so one extra language roughly doubles the time.")
            }
        }
        .navigationTitle("Additional languages")
    }
}

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
                                .foregroundStyle(Color.brandRed)
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
