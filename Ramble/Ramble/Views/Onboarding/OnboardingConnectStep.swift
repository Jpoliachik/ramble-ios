//
//  OnboardingConnectStep.swift
//  Ramble
//
//  Connect an agent on one screen: 1 copy the message, 2 paste it to your
//  agent, 3 wait for it to connect. The steps fill in as you go and the
//  message never leaves, so it can be copied again at any point. Continue
//  stays disabled until the relay reports a new connection.
//
//  The relay is only checked while this screen is up and a code is live,
//  same as the existing connect sheet.
//

import SwiftUI
import UIKit

struct OnboardingConnectStep: View {
    var continueTitle = "Continue"
    var laterTitle = "Set up later"
    let onContinue: () -> Void
    let onLater: () -> Void

    @ObservedObject private var relay = RelayService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: ConnectStage = .copy
    @State private var pairCode: RelayPairCode?
    /// Connections when the current code was issued; more than this means it was used.
    @State private var baselineCount = 0
    @State private var justCopied = false
    /// The app went to the background after copying, i.e. they went to paste.
    @State private var leftAfterCopy = false
    @State private var isLoadingCode = false
    @State private var errorMessage: String?

    private static let pollInterval: Duration = .seconds(4)

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeadline(size: 34, alignment: .leading) {
                    Text("Connect ") + Text("your agent.").italic().foregroundColor(Color.obInkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    ConnectStepRow(number: 1, state: rowState(0), title: "Copy this message", showsLine: true) {
                        messageBox
                    }
                    ConnectStepRow(number: 2, state: rowState(1), title: "Paste it to your agent", showsLine: true) {
                        Text("Send it in any chat with your agent.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.obInkSoft)
                    }
                    ConnectStepRow(
                        number: 3,
                        state: rowState(2),
                        title: stepThreeTitle,
                        showsDots: stage == .waiting,
                        showsLine: false
                    ) {
                        stepThreeDetail
                    }
                }

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Button("Try again") { Task { await requestCode() } }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.brandAmber)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .animation(.smooth(duration: 0.3), value: stage)
        } bottomBar: {
            VStack(spacing: 0) {
                OnboardingPrimaryButton(title: continueTitle, isDisabled: stage != .connected, action: onContinue)
                if stage == .connected {
                    Color.clear.frame(height: 47)
                } else {
                    OnboardingSecondaryLink(title: laterTitle, action: onLater)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .task { if pairCode == nil { await requestCode() } }
        .task(id: pairCode?.code) { await waitForAgent() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if stage == .paste { leftAfterCopy = true }
            case .active:
                if leftAfterCopy && stage == .paste { stage = .waiting }
            default:
                break
            }
        }
    }

    // MARK: - Pieces

    private var messageBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PairingMessage.text(code: pairCode?.code ?? "XXXX-XXXX"))
                .font(.system(size: 15))
                .foregroundStyle(Color.obInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .redacted(reason: pairCode == nil ? .placeholder : [])

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = pairCode.map { Int($0.expiresAt.timeIntervalSince(context.date)) } ?? 0
                let expired = pairCode != nil && remaining <= 0
                HStack {
                    Text(metaText(remaining: remaining, expired: expired))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.obInkFaint)
                        .monospacedDigit()
                    Spacer()
                    copyButton(expired: expired)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.top, 8)
    }

    private func metaText(remaining: Int, expired: Bool) -> String {
        if pairCode == nil { return isLoadingCode ? "Getting a code…" : " " }
        if expired { return "This code expired" }
        return "Works once · \(remaining / 60):\(String(format: "%02d", remaining % 60)) left"
    }

    @ViewBuilder
    private func copyButton(expired: Bool) -> some View {
        if expired {
            Button {
                Task { await requestCode() }
            } label: {
                Label("New code", systemImage: "arrow.clockwise")
                    .modifier(CopyCapsule(prominent: true))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingCode)
        } else {
            Button(action: copy) {
                Label(copyTitle, systemImage: justCopied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .modifier(CopyCapsule(prominent: stage == .copy && !justCopied))
            }
            .buttonStyle(.plain)
            .disabled(pairCode == nil)
        }
    }

    private var copyTitle: String {
        if justCopied { return "Copied" }
        return stage == .copy ? "Copy" : "Copy again"
    }

    private var stepThreeTitle: String {
        switch stage {
        case .connected: return "Connected"
        case .waiting: return "Waiting for your agent"
        default: return "Wait for it to connect"
        }
    }

    @ViewBuilder
    private var stepThreeDetail: some View {
        switch stage {
        case .waiting:
            Text("Usually under a minute.")
                .font(.system(size: 15))
                .foregroundStyle(Color.obInkSoft)
        case .connected:
            Label("Checked in just now", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brandAmber)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Color.brandAmberSoft, in: Capsule())
                .padding(.top, 4)
                .transition(.scale.combined(with: .opacity))
        default:
            EmptyView()
        }
    }

    private func rowState(_ index: Int) -> ConnectStepRowState {
        let current = stage.rawValue
        if index < current { return .done }
        if index == current { return .current }
        return .upcoming
    }

    // MARK: - Actions

    private func copy() {
        guard let pairCode else { return }
        UIPasteboard.general.string = PairingMessage.text(code: pairCode.code)
        HapticService.success()
        justCopied = true
        if stage == .copy { stage = .paste }
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }

    private func requestCode() async {
        isLoadingCode = true
        errorMessage = nil
        defer { isLoadingCode = false }
        do {
            _ = try? await relay.refreshConnections()
            baselineCount = relay.connections.count
            pairCode = try await relay.createPairCode()
            if stage != .connected {
                stage = .copy
                leftAfterCopy = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Checks the relay every few seconds while a live code is on screen.
    /// Errors stay quiet; the next tick retries.
    private func waitForAgent() async {
        guard let code = pairCode else { return }
        while !Task.isCancelled, code.expiresAt > .now, stage != .connected {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled,
                  let list = try? await relay.refreshConnections(),
                  list.count > baselineCount
            else { continue }
            HapticService.success()
            stage = .connected
            return
        }
    }
}

// MARK: - Stage

private enum ConnectStage: Int {
    case copy, paste, waiting, connected
}

enum ConnectStepRowState {
    case upcoming, current, done
}

// MARK: - Step row

/// A numbered step with a connecting line down to the next one. The line
/// turns amber once the step is done.
struct ConnectStepRow<Detail: View>: View {
    let number: Int
    let state: ConnectStepRowState
    let title: String
    var showsDots: Bool = false
    let showsLine: Bool
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                StepBadge(number: number, state: state)
                if showsLine {
                    Capsule()
                        .fill(state == .done ? Color.brandAmber : Color.obHair)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(state == .upcoming ? Color.obInkFaint : Color.obInk)
                    if showsDots {
                        WaitingDots()
                    }
                }
                detail()
            }
            .padding(.top, 3)
            .padding(.bottom, showsLine ? 20 : 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StepBadge: View {
    let number: Int
    let state: ConnectStepRowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.onOnboardingAmber)
            } else {
                Text("\(number)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state == .current ? Color.brandAmber : Color.obInkFaint)
            }
        }
        .frame(width: 28, height: 28)
        .background {
            if state == .current && !reduceMotion {
                Circle()
                    .stroke(Color.brandAmber, lineWidth: 2)
                    .phaseAnimator([false, true]) { ring, expanded in
                        ring
                            .scaleEffect(expanded ? 1.7 : 1)
                            .opacity(expanded ? 0 : 0.5)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.4) : .linear(duration: 0)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch state {
        case .done: return Color.brandAmber
        case .current: return Color.brandAmberSoft
        case .upcoming: return Color(.tertiarySystemFill)
        }
    }
}

/// Three amber dots that bounce while waiting.
private struct WaitingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = max(0, sin(t * 5 - Double(index) * 0.7))
                    Circle()
                        .fill(Color.brandAmber)
                        .frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * wave)
                        .offset(y: -3 * wave)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The small Copy / Copy again / New code capsule under the message.
private struct CopyCapsule: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(prominent ? Color.onOnboardingAmber : Color.obInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(prominent ? Color.brandAmber : Color(.tertiarySystemFill), in: Capsule())
    }
}

extension Color {
    /// Label color on a filled amber control. White lacks contrast on the
    /// bright dark-mode amber, so dark mode uses near-black.
    static let onOnboardingAmber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1F / 255, green: 0x14 / 255, blue: 0x04 / 255, alpha: 1)
            : .white
    })
}

#Preview {
    OnboardingConnectStep(onContinue: {}, onLater: {})
        .background(Color(.systemGroupedBackground))
}
