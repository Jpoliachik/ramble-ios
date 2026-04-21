//
//  OnboardingView.swift
//  Ramble
//

import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var currentStep: Step = .hero
    @State private var selectedProvider: TranscriptionProvider = .appleSpeech
    @State private var selectedCloudModel: CloudModel = .whisperLargeV3Turbo
    @State private var webhookURL: String = ""
    @State private var webhookURLError: String?
    @State private var showPaywall = false
    @State private var showWebhookInfo = false

    @ObservedObject private var subscriptionService = SubscriptionService.shared

    enum Step: Int, CaseIterable {
        case hero, mic, transcription, webhook

        var setupIndex: Int? {
            switch self {
            case .hero: return nil
            case .mic: return 1
            case .transcription: return 2
            case .webhook: return 3
            }
        }

        static let setupCount = 3
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            Group {
                switch currentStep {
                case .hero:
                    HeroStep(
                        onContinue: { advance() },
                        onDismiss: { finish() }
                    )
                    .transition(stepTransition)
                case .mic:
                    MicStep(
                        stepIndex: currentStep.setupIndex ?? 1,
                        totalSteps: Step.setupCount,
                        onContinue: advance,
                        onSkip: advance
                    )
                    .transition(stepTransition)
                case .transcription:
                    TranscriptionStep(
                        stepIndex: currentStep.setupIndex ?? 2,
                        totalSteps: Step.setupCount,
                        selectedProvider: $selectedProvider,
                        selectedCloudModel: $selectedCloudModel,
                        isPremium: subscriptionService.isPremium,
                        onTapCloudModel: handleCloudModelTap,
                        onContinue: advance,
                        onSkip: advance
                    )
                    .transition(stepTransition)
                case .webhook:
                    WebhookStep(
                        stepIndex: currentStep.setupIndex ?? 3,
                        totalSteps: Step.setupCount,
                        webhookURL: $webhookURL,
                        webhookURLError: $webhookURLError,
                        onShowInfo: { showWebhookInfo = true },
                        onFinish: finish,
                        onSkip: finish
                    )
                    .transition(stepTransition)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
            SubscriptionView()
        }
        .sheet(isPresented: $showWebhookInfo) {
            WebhookInfoSheet()
        }
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
        let next = Step(rawValue: currentStep.rawValue + 1) ?? .webhook
        withAnimation {
            currentStep = next
        }
    }

    private func handleCloudModelTap(_ model: CloudModel) {
        HapticService.buttonTap()
        selectedCloudModel = model
        if subscriptionService.isPremium {
            selectedProvider = .cloudTranscription
        } else {
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

        HapticService.recordStop()
        hasCompletedOnboarding = true
    }
}

// MARK: - Hero step

private struct HeroStep: View {
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with dismiss
            HStack {
                Spacer()
                Button(action: {
                    HapticService.buttonTap()
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(.secondarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                    Text("Ramble")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .italic()
                }

                Text("Talk, don't think.")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Tap the red button. Ramble your thoughts. Watch them land wherever you work.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 8)

            HeroDemoStage()
                .frame(maxHeight: .infinity)
                .padding(.vertical, 16)

            PrimaryButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }
}

// MARK: - Hero demo stage

private struct HeroDemoStage: View {
    enum Phase {
        case idle, recording, transcribing, sending, delivered
    }

    @State private var phase: Phase = .idle
    @State private var simulatedLevel: Float = 0
    @State private var transcriptRevealed: Int = 0
    @State private var deliveredIndex: Int = -1
    @State private var packetsInFlight: [PacketAnimation] = []
    @State private var levelTimer: Timer?
    @State private var phaseTask: Task<Void, Never>?

    private let fullTranscript = "Remember to text Sarah about the Q2 demo."

    private var revealedTranscript: String {
        String(fullTranscript.prefix(transcriptRevealed))
    }

    var body: some View {
        VStack(spacing: 18) {
            // Destinations row
            HStack(spacing: 16) {
                DestinationChip(
                    icon: "cpu",
                    label: "Agent",
                    isHighlighted: deliveredIndex >= 0
                )
                DestinationChip(
                    icon: "bolt.fill",
                    label: "Zapier",
                    isHighlighted: deliveredIndex >= 1
                )
                DestinationChip(
                    icon: "doc.text.fill",
                    label: "Notion",
                    isHighlighted: deliveredIndex >= 2
                )
            }
            .padding(.top, 4)

            // Transcript bubble
            TranscriptBubble(text: revealedTranscript, isVisible: phase == .transcribing || phase == .sending || phase == .delivered)
                .frame(minHeight: 56)
                .padding(.horizontal, 24)
                .opacity(phase == .idle || phase == .recording ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: phase)

            Spacer(minLength: 0)

            // Waveform (visible while recording)
            DemoWaveform(level: simulatedLevel)
                .opacity(phase == .recording ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: phase)
                .frame(height: 44)

            // Red button with packet effect
            ZStack {
                // Soft pulse glow when idle
                if phase == .idle {
                    IdlePulseRing()
                }

                DemoRedButton(isRecording: phase == .recording) {
                    triggerDemo()
                }

                // Packet dots flying from button to destinations
                ForEach(packetsInFlight) { packet in
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: packet.offsetX, y: packet.offsetY)
                        .opacity(packet.opacity)
                }
            }
            .frame(height: 120)
        }
        .onAppear {
            // Auto-start the demo shortly after the hero appears
            phaseTask = Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !Task.isCancelled { triggerDemo() }
            }
        }
        .onDisappear {
            phaseTask?.cancel()
            levelTimer?.invalidate()
        }
    }

    private func triggerDemo() {
        phaseTask?.cancel()
        phaseTask = Task {
            await runCycle()
        }
    }

    @MainActor
    private func runCycle() async {
        // Reset
        levelTimer?.invalidate()
        simulatedLevel = 0
        transcriptRevealed = 0
        deliveredIndex = -1
        packetsInFlight = []

        // Phase: recording (~2.2s)
        phase = .recording
        HapticService.buttonTap()
        startSimulatedLevels()
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        levelTimer?.invalidate()
        simulatedLevel = 0

        // Phase: transcribing (typewriter reveal ~1.4s)
        phase = .transcribing
        let totalChars = fullTranscript.count
        let stepNanos: UInt64 = 35_000_000  // 35ms per char
        for i in 1...totalChars {
            if Task.isCancelled { return }
            transcriptRevealed = i
            try? await Task.sleep(nanoseconds: stepNanos)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Phase: sending — shoot 3 packets to destinations
        phase = .sending
        for i in 0..<3 {
            launchPacket(toIndex: i)
            try? await Task.sleep(nanoseconds: 280_000_000)
            deliveredIndex = i
            HapticService.buttonTap()
        }
        try? await Task.sleep(nanoseconds: 900_000_000)

        // Hold delivered
        phase = .delivered
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // Reset to idle (fade everything out)
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .idle
            transcriptRevealed = 0
            deliveredIndex = -1
        }
        packetsInFlight = []
    }

    private func startSimulatedLevels() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            Task { @MainActor in
                // Wandering fake audio level with randomness
                let target = Float.random(in: 0.25...0.95)
                withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                    simulatedLevel = target
                }
            }
        }
    }

    private struct PacketAnimation: Identifiable {
        let id = UUID()
        var offsetX: CGFloat
        var offsetY: CGFloat
        var opacity: Double
    }

    private func launchPacket(toIndex index: Int) {
        // Packets fly from the button (bottom center, offset 0,0) toward the chip position.
        // Chips are ~top of stage: we'll approximate targets by index (left/center/right).
        let xTargets: [CGFloat] = [-110, 0, 110]
        let target = xTargets[index]
        let yTarget: CGFloat = -260

        let packet = PacketAnimation(offsetX: 0, offsetY: 0, opacity: 1)
        packetsInFlight.append(packet)
        let id = packet.id

        withAnimation(.easeOut(duration: 0.55)) {
            if let idx = packetsInFlight.firstIndex(where: { $0.id == id }) {
                packetsInFlight[idx].offsetX = target
                packetsInFlight[idx].offsetY = yTarget
            }
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.35)) {
            if let idx = packetsInFlight.firstIndex(where: { $0.id == id }) {
                packetsInFlight[idx].opacity = 0
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            packetsInFlight.removeAll { $0.id == id }
        }
    }
}

private struct IdlePulseRing: View {
    @State private var active = false

    var body: some View {
        Circle()
            .fill(Color.red.opacity(0.18))
            .frame(width: 120, height: 120)
            .scaleEffect(active ? 1.55 : 1.0)
            .opacity(active ? 0 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    active = true
                }
            }
    }
}

private struct DemoRedButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize: CGFloat = 84
    private let innerSize: CGFloat = 72

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.8), lineWidth: 4)
                    .frame(width: buttonSize, height: buttonSize)

                RoundedRectangle(cornerRadius: isRecording ? 10 : innerSize / 2)
                    .fill(Color.red)
                    .frame(
                        width: isRecording ? 28 : innerSize,
                        height: isRecording ? 28 : innerSize
                    )
                    .scaleEffect(isRecording ? pulseScale : 1.0)
                    .shadow(color: Color.red.opacity(0.35), radius: 18, y: 6)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseScale = 1.12
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
}

private struct DemoWaveform: View {
    let level: Float

    private let barCount = 9
    private let barWidth: CGFloat = 6
    private let barSpacing: CGFloat = 5

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                DemoBar(index: i, baseLevel: level)
            }
        }
    }
}

private struct DemoBar: View {
    let index: Int
    let baseLevel: Float

    @State private var height: CGFloat = 8

    private let minHeight: CGFloat = 8
    private let maxHeight: CGFloat = 40

    var body: some View {
        Capsule()
            .fill(Color.red)
            .frame(width: 6, height: height)
            .onChange(of: baseLevel) { _, newLevel in
                // Each bar picks a slightly varied target so the wave looks organic
                let variance = Float.random(in: 0.6...1.0)
                let target = min(max(newLevel * variance, 0.15), 1.0)
                let delay = Double(index) * 0.03
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
                        height = minHeight + (maxHeight - minHeight) * CGFloat(target)
                    }
                }
            }
    }
}

private struct TranscriptBubble: View {
    let text: String
    let isVisible: Bool

    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.red.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct DestinationChip: View {
    let icon: String
    let label: String
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isHighlighted ? Color.red.opacity(0.15) : Color(.secondarySystemFill))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isHighlighted ? Color.red : Color.secondary)
            }
            .scaleEffect(isHighlighted ? 1.08 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHighlighted)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isHighlighted ? .primary : .secondary)
        }
    }
}

// MARK: - Mic step

private struct MicStep: View {
    let stepIndex: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var permissionStatus: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
    @State private var isRequesting = false
    @State private var iconPulse = false

    var body: some View {
        StepScaffold(
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            title: "Enable your microphone",
            subtitle: "Ramble only listens while you're holding the record button. Audio stays on your device unless you pick cloud transcription.",
            primaryTitle: buttonLabel,
            isPrimaryLoading: isRequesting,
            onPrimary: handleTap,
            onSkip: onSkip
        ) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .scaleEffect(iconPulse ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: iconPulse)
                Image(systemName: "mic.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.red)
            }
            .onAppear { iconPulse = true }
        }
    }

    private var buttonLabel: String {
        switch permissionStatus {
        case .granted: return "Continue"
        case .denied: return "Continue anyway"
        default: return "Enable microphone"
        }
    }

    private func handleTap() {
        if permissionStatus != .undetermined {
            onContinue()
            return
        }
        isRequesting = true
        AVAudioSession.sharedInstance().requestRecordPermission { _ in
            DispatchQueue.main.async {
                isRequesting = false
                permissionStatus = AVAudioSession.sharedInstance().recordPermission
                onContinue()
            }
        }
    }
}

// MARK: - Transcription step

private struct TranscriptionStep: View {
    let stepIndex: Int
    let totalSteps: Int
    @Binding var selectedProvider: TranscriptionProvider
    @Binding var selectedCloudModel: CloudModel
    let isPremium: Bool
    let onTapCloudModel: (CloudModel) -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        StepScaffold(
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            title: "Pick a transcription engine",
            subtitle: "Apple Speech is free and on-device. Cloud models are more accurate for accents, noise, and clean punctuation.",
            primaryTitle: "Continue",
            isPrimaryLoading: false,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            ScrollView {
                VStack(spacing: 10) {
                    ProviderRowView(
                        provider: .appleSpeech,
                        isSelected: selectedProvider == .appleSpeech,
                        onSelect: {
                            HapticService.buttonTap()
                            selectedProvider = .appleSpeech
                        }
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
            }
        }
    }

    private func rowBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Color.red : Color.clear, lineWidth: 2)
            )
    }
}

// MARK: - Webhook step

private struct WebhookStep: View {
    let stepIndex: Int
    let totalSteps: Int
    @Binding var webhookURL: String
    @Binding var webhookURLError: String?
    let onShowInfo: () -> Void
    let onFinish: () -> Void
    let onSkip: () -> Void

    @FocusState private var urlFieldFocused: Bool

    private var hasURL: Bool {
        !webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canFinishWithURL: Bool {
        hasURL && webhookURLError == nil
    }

    var body: some View {
        StepScaffold(
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            title: "Connect your workflow",
            subtitle: "Pipe every transcript as JSON to an endpoint you control — an AI agent, Zapier catch hook, n8n, or a Pipedream → Notion flow.",
            primaryTitle: canFinishWithURL ? "Save & start rambling" : "Start rambling",
            isPrimaryLoading: false,
            onPrimary: onFinish,
            onSkip: onSkip
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Webhook URL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        TextField("https://your-webhook.example.com", text: $webhookURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($urlFieldFocused)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .onChange(of: webhookURL) { validate() }

                        if let error = webhookURLError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if hasURL {
                            Label("Looks good — we'll sign every POST with your secret.", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Popular destinations")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        PlatformHint(icon: "cpu", title: "Your own agent", subtitle: "Any HTTPS endpoint that parses JSON.")
                        PlatformHint(icon: "bolt.fill", title: "Zapier · Make · n8n", subtitle: "Create a catch webhook, paste the URL here.")
                        PlatformHint(icon: "square.stack.3d.up.fill", title: "Notion via Pipedream", subtitle: "Pipedream source → Notion row.")
                    }

                    Button {
                        HapticService.buttonTap()
                        onShowInfo()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("What's a webhook?")
                        }
                        .font(.footnote)
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollDismissesKeyboard(.interactively)
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

// MARK: - Shared scaffold

private struct StepScaffold<Content: View>: View {
    let stepIndex: Int
    let totalSteps: Int
    let title: String
    let subtitle: String
    let primaryTitle: String
    let isPrimaryLoading: Bool
    let onPrimary: () -> Void
    let onSkip: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                StepPill(index: stepIndex, total: totalSteps)
                    .padding(.top, 20)

                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            VStack(spacing: 14) {
                Button(action: {
                    HapticService.buttonTap()
                    onSkip()
                }) {
                    Text("Skip for now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                PrimaryButton(title: primaryTitle, isLoading: isPrimaryLoading, action: onPrimary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct StepPill: View {
    let index: Int
    let total: Int

    var body: some View {
        Text("Step \(index)/\(total)")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticService.buttonTap()
            action()
        }) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red)
                    .shadow(color: Color.red.opacity(0.25), radius: 10, y: 4)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
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
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.red.opacity(0.12))
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
