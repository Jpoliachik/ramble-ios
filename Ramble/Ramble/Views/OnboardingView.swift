//
//  OnboardingView.swift
//  Ramble
//

import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var currentStep = 0
    @State private var selectedProvider: TranscriptionProvider = .appleSpeech
    @State private var selectedCloudModel: CloudModel = .whisperLargeV3Turbo
    @State private var webhookURL: String = ""
    @State private var webhookURLError: String?
    @State private var showPaywall = false
    @State private var showWebhookInfo = false

    @ObservedObject private var subscriptionService = SubscriptionService.shared

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            progressIndicator
                .padding(.top, 20)
                .padding(.horizontal, 24)

            ZStack {
                switch currentStep {
                case 0:
                    OnboardingIntroStep(onContinue: advance)
                        .transition(stepTransition)
                case 1:
                    OnboardingMicStep(onContinue: advance)
                        .transition(stepTransition)
                case 2:
                    OnboardingTranscriptionStep(
                        selectedProvider: $selectedProvider,
                        selectedCloudModel: $selectedCloudModel,
                        isPremium: subscriptionService.isPremium,
                        onTapCloudModel: handleCloudModelTap,
                        onContinue: advance
                    )
                    .transition(stepTransition)
                case 3:
                    OnboardingWebhookStep(
                        webhookURL: $webhookURL,
                        webhookURLError: $webhookURLError,
                        onShowInfo: { showWebhookInfo = true },
                        onSkip: finish,
                        onFinish: finish
                    )
                    .transition(stepTransition)
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.28), value: currentStep)
        }
        .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
            SubscriptionView()
        }
        .sheet(isPresented: $showWebhookInfo) {
            WebhookInfoSheet()
        }
    }

    // MARK: - Subviews

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { idx in
                Capsule()
                    .fill(idx <= currentStep ? Color.red : Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: currentStep)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    // MARK: - Actions

    private func advance() {
        HapticService.buttonTap()
        withAnimation {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func handleCloudModelTap(_ model: CloudModel) {
        selectedCloudModel = model
        if subscriptionService.isPremium {
            selectedProvider = .cloudTranscription
        } else {
            // Stage the choice; actual switch happens if user subscribes
            showPaywall = true
        }
    }

    private func handlePaywallDismiss() {
        if subscriptionService.isPremium {
            selectedProvider = .cloudTranscription
        }
    }

    private func finish() {
        let service = SettingsService.shared
        let current = service.load()
        let cleanedURL = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidURL = !cleanedURL.isEmpty && webhookURLError == nil

        let settings = Settings(
            transcriptionProvider: selectedProvider,
            cloudModel: selectedCloudModel,
            webhookEnabled: hasValidURL,
            webhookURL: hasValidURL ? cleanedURL : nil,
            webhookSecret: current.webhookSecret,
            deviceId: current.deviceId,
            appearanceMode: current.appearanceMode
        )
        service.save(settings)

        HapticService.buttonTap()
        hasCompletedOnboarding = true
    }
}

// MARK: - Step 1: Intro

private struct OnboardingIntroStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 18, height: 18)
                    Text("Ramble")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .italic()
                }

                Text("Talk first. Organize later.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 22) {
                ValueRow(
                    icon: "mic.fill",
                    color: .red,
                    title: "Capture thoughts instantly",
                    subtitle: "Tap once. Speak. Done."
                )
                ValueRow(
                    icon: "text.alignleft",
                    color: .blue,
                    title: "Get accurate transcripts",
                    subtitle: "On-device by default. Cloud models if you want them."
                )
                ValueRow(
                    icon: "bolt.horizontal.fill",
                    color: .orange,
                    title: "Send them anywhere",
                    subtitle: "Webhook into your agent, Zapier, Notion — whatever you run."
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            Button(action: onContinue) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Step 2: Mic permission

private struct OnboardingMicStep: View {
    let onContinue: () -> Void

    @State private var permissionStatus: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                }

                VStack(spacing: 10) {
                    Text("Let Ramble hear you")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Ramble only listens while you're holding the record button. Audio stays on your device unless you choose cloud transcription.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: requestPermission) {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(buttonLabel)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isRequesting)

                if permissionStatus == .denied {
                    Text("You can enable microphone access in Settings later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private var buttonLabel: String {
        switch permissionStatus {
        case .granted: return "Continue"
        case .denied: return "Continue anyway"
        default: return "Enable microphone"
        }
    }

    private func requestPermission() {
        if permissionStatus != .undetermined {
            onContinue()
            return
        }

        isRequesting = true
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                isRequesting = false
                permissionStatus = AVAudioSession.sharedInstance().recordPermission
                _ = granted
                onContinue()
            }
        }
    }
}

// MARK: - Step 3: Transcription

private struct OnboardingTranscriptionStep: View {
    @Binding var selectedProvider: TranscriptionProvider
    @Binding var selectedCloudModel: CloudModel
    let isPremium: Bool
    let onTapCloudModel: (CloudModel) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Pick a transcription engine")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Apple Speech runs free on-device. Cloud models are more accurate — especially for accents, noisy rooms, or clean punctuation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 10) {
                    ProviderRowView(
                        provider: .appleSpeech,
                        isSelected: selectedProvider == .appleSpeech,
                        onSelect: { selectedProvider = .appleSpeech }
                    )
                    .padding(12)
                    .background(rowBackground(selected: selectedProvider == .appleSpeech))

                    ForEach(CloudModel.allCases) { model in
                        let isSelected = selectedProvider == .cloudTranscription && selectedCloudModel == model
                        CloudModelRowView(
                            model: model,
                            isSelected: isSelected,
                            isPremiumLocked: !isPremium,
                            onSelect: { onTapCloudModel(model) }
                        )
                        .padding(12)
                        .background(rowBackground(selected: isSelected))
                    }
                }
                .padding(.horizontal, 20)
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func rowBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
    }
}

// MARK: - Step 4: Webhook

private struct OnboardingWebhookStep: View {
    @Binding var webhookURL: String
    @Binding var webhookURLError: String?
    let onShowInfo: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void

    @FocusState private var urlFieldFocused: Bool

    private var hasURL: Bool {
        !webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canFinishWithURL: Bool {
        hasURL && webhookURLError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Text("Send transcripts anywhere")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("Ramble POSTs every transcript as JSON to a URL you choose. Wire it into your agent, a Zapier catch hook, Make, n8n, or a Pipedream → Notion workflow.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Webhook URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://your-webhook.example.com", text: $webhookURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($urlFieldFocused)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .onChange(of: webhookURL) {
                                validate()
                            }

                        if let error = webhookURLError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if hasURL {
                            Label("Looks good — we'll send a signed POST here after every transcription.", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Popular destinations")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        PlatformHint(
                            icon: "cpu",
                            title: "Your own agent / backend",
                            subtitle: "Any HTTPS endpoint that parses JSON."
                        )
                        PlatformHint(
                            icon: "bolt.fill",
                            title: "Zapier / Make / n8n",
                            subtitle: "Create a catch webhook, paste the URL here."
                        )
                        PlatformHint(
                            icon: "square.stack.3d.up.fill",
                            title: "Notion via Pipedream",
                            subtitle: "Pipedream source → Notion database row."
                        )
                    }
                    .padding(.horizontal, 24)

                    Button(action: onShowInfo) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("What's a webhook?")
                        }
                        .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.bottom, 16)
            }

            VStack(spacing: 10) {
                Button(action: onFinish) {
                    Text(canFinishWithURL ? "Save & finish" : "Skip for now")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(hasURL && webhookURLError != nil)

                if canFinishWithURL {
                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("You can add one later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onTapGesture {
            urlFieldFocused = false
        }
    }

    private func validate() {
        let trimmed = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            webhookURLError = nil
            return
        }
        webhookURLError = WebhookQueueService.validateWebhookURL(trimmed)
    }
}

// MARK: - Shared row components

private struct ValueRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(color.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PlatformHint: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingView()
}
