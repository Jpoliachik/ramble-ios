//
//  ConnectAgentView.swift
//  Ramble
//
//  "Your agent": how the connected agent is doing, plus the relay's privacy
//  controls. Opening it never makes a pairing code. Connecting (or
//  connecting again) is an explicit tap that opens the same one-screen
//  Connect flow as onboarding, and that's when the code is made.
//
//  States: connected, quiet (something is waiting and the agent hasn't
//  checked in for a while), and not connected.
//

import SwiftUI

struct ConnectAgentView: View {
    @ObservedObject private var relay = RelayService.shared
    @Environment(\.dismiss) private var dismiss

    /// Opens straight onto the Connect flow, e.g. from a "Connect" button.
    private let startPairing: Bool

    @State private var isPairing: Bool
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var note: String?
    @State private var showDeleteConfirmation = false
    @State private var showDisconnectConfirmation = false
    /// The one agent to disconnect, when several are connected.
    @State private var disconnectTarget: RelayConnection?

    init(startPairing: Bool = false) {
        self.startPairing = startPairing
        _isPairing = State(initialValue: startPairing)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isPairing {
                    OnboardingConnectStep(
                        continueTitle: "Done",
                        laterTitle: "Cancel",
                        onContinue: leavePairing,
                        onLater: leavePairing
                    )
                } else {
                    statusScreen
                }
            }
            .animation(.smooth, value: isPairing)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                // The Connect flow has its own Cancel at the bottom.
                if !isPairing {
                    ToolbarItem(placement: .confirmationAction) {
                        // Button(role: .close) is iOS 26-only; the iOS target is
                        // 18.6, so use a plain button to keep the build compiling.
                        Button("Close") { dismiss() }
                    }
                }
            }
            .confirmationDialog(
                relay.connections.count > 1 ? "Disconnect your agents?" : "Disconnect your agent?",
                isPresented: $showDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        await run {
                            for connection in relay.connections {
                                try await relay.disconnect(connection)
                            }
                        }
                    }
                }
            } message: {
                Text(relay.connections.count > 1
                     ? "They lose access immediately, and anything waiting for them is deleted."
                     : "It loses access immediately, and anything waiting for it is deleted.")
            }
            .confirmationDialog(
                "Disconnect \(disconnectTarget.map(AgentHealth.displayName) ?? "this agent")?",
                isPresented: Binding(
                    get: { disconnectTarget != nil },
                    set: { if !$0 { disconnectTarget = nil } }
                ),
                titleVisibility: .visible,
                presenting: disconnectTarget
            ) { connection in
                Button("Disconnect", role: .destructive) {
                    Task { await run { try await relay.disconnect(connection) } }
                }
            } message: { _ in
                Text("It loses access immediately, and anything waiting for it is deleted. Your other agents stay connected.")
            }
            .confirmationDialog(
                "Delete waiting notes?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await run {
                            let count = try await relay.deleteAllWaiting()
                            note = count == 0 ? "Nothing was waiting." : "Deleted \(count) waiting."
                        }
                    }
                }
            } message: {
                Text("Notes your agent hasn't picked up are deleted from the relay. Notes still being transcribed will still be sent. Your agent stays connected, and the copies on this phone stay.")
            }
        }
    }

    /// Done or Cancel on the Connect flow: back to the status screen, or
    /// close the sheet if it was opened just to connect.
    private func leavePairing() {
        if startPairing {
            dismiss()
        } else {
            isPairing = false
        }
    }

    // MARK: - Status

    private var statusScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(relay.connections.count > 1 ? "Your agents" : "Your agent")
                    .font(.system(size: 32, design: .serif).weight(.medium))
                    .tracking(-0.3)
                    .foregroundStyle(Color.obInk)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if relay.connections.isEmpty {
                    notConnected
                } else {
                    ForEach(relay.connections) { connection in
                        AgentStatusCard(
                            connection: connection,
                            onConnectAgain: {
                                HapticService.buttonTap()
                                note = nil
                                isPairing = true
                            },
                            // With one agent, the Disconnect row below covers it.
                            onDisconnect: relay.connections.count > 1 ? { disconnectTarget = connection } : nil
                        )
                    }
                    privacyNote
                        .padding(.top, 14)
                    actions
                    // Most people use one agent, so this stays a quiet footnote.
                    Button {
                        HapticService.buttonTap()
                        note = nil
                        isPairing = true
                    } label: {
                        Text("Using more than one agent? **Connect another**")
                            .font(.footnote)
                            .foregroundStyle(Color.obInkFaint)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Color.connectAmberText)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await run { try await relay.refreshConnections() } }
        .task { await run { try await relay.refreshConnections() } }
    }

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandAmber)
                        .frame(width: 36, height: 36)
                        .background(Color.brandAmberSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("No agent yet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.obInk)
                }
                Text("Notes stay on your iPhone until you connect one. It sets itself up from one message.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.obInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle()
                    .fill(Color.obHair)
                    .frame(height: 1)
                Text("Works with Muse, Grok Bot, ChatGPT and more")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            OnboardingPrimaryButton(title: "Connect your agent") {
                isPairing = true
            }
            .padding(.top, 4)
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEMPORARY BY DESIGN")
                .font(.system(size: 12, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(Color.obInkFaint)
                .padding(.horizontal, 4)
            Text(PrivacyCopy.relay)
                .font(.subheadline)
                .foregroundStyle(Color.obInkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete waiting notes")
                    Spacer()
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Color.obInkFaint)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            Divider().padding(.leading, 16)
            Button(role: .destructive) {
                showDisconnectConfirmation = true
            } label: {
                HStack {
                    Text(relay.connections.count > 1 ? "Disconnect all" : "Disconnect")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .disabled(isWorking)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 6)
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do { try await action() } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }
}

// MARK: - Agent health

/// How one connected agent is doing, in the same words as Home and Settings.
enum AgentHealth: Equatable {
    case connected
    /// Notes are waiting and it hasn't checked in within the
    /// stuck-note threshold.
    case quiet

    @MainActor
    init(_ connection: RelayConnection, now: Date = Date()) {
        let threshold = HomeStatus.longWait
        let stale = connection.lastPullAt.map { now.timeIntervalSince($0) > threshold } ?? true
        self = connection.pending > 0 && stale ? .quiet : .connected
    }

    /// The name the agent gave itself at pairing, or a plain fallback.
    static func displayName(_ connection: RelayConnection) -> String {
        connection.name ?? "Agent"
    }

    /// "Checked in 2m ago · nothing waiting".
    static func summary(_ connection: RelayConnection) -> String {
        let checked: String
        if let last = connection.lastPullAt {
            let age = HomeStatusLine.age(since: last)
            // "Last checked in" under a quiet card's "Hasn't checked in" heading.
            let verb = connection.pending > 0 && age != "now" ? "Last checked in" : "Checked in"
            checked = age == "now" ? "Checked in just now" : "\(verb) \(age) ago"
        } else {
            checked = "Hasn't checked in yet"
        }
        let waiting = connection.pending == 0 ? "nothing waiting" : "\(connection.pending) waiting"
        return "\(checked) · \(waiting)"
    }
}

/// The status card on "Your agent": green when it's fine, amber with
/// "Connect again" when it has gone quiet.
private struct AgentStatusCard: View {
    let connection: RelayConnection
    let onConnectAgain: () -> Void
    /// Shown only when several agents are connected.
    var onDisconnect: (() -> Void)? = nil

    var body: some View {
        let health = AgentHealth(connection)
        VStack(alignment: .leading, spacing: 6) {
            if let name = connection.name {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.obInkFaint)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(health == .quiet ? Color.brandAmber : Color.green)
                    .frame(width: 10, height: 10)
                Text(health == .quiet ? "Hasn't checked in" : "Connected")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.obInk)
                Spacer(minLength: 8)
                if let onDisconnect {
                    // Quiet grey: the confirmation dialog carries the red.
                    Button("Disconnect", action: onDisconnect)
                        .font(.system(size: 14))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.obInkFaint)
                }
            }
            Text(AgentHealth.summary(connection))
                .font(.system(size: 15))
                .foregroundStyle(Color.obInkSoft)
            if let hook = connection.hook {
                HStack(spacing: 4) {
                    Image(systemName: hook.isFailing ? "bolt.slash" : "bolt.fill")
                    Text(hook.isFailing ? "Wake-up hook isn't answering" : "Wakes up when a note arrives")
                }
                .font(.system(size: 13))
                .foregroundStyle(hook.isFailing ? Color.connectAmberText : Color.obInkFaint)
            }

            if health == .quiet {
                Text("If your agent lost its setup, connect it again with a fresh message.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.obInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                OnboardingPrimaryButton(title: "Connect again", action: onConnectAgain)
                    .padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if health == .quiet {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.brandAmber, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private extension Color {
    /// Brand amber for text: #b45309 in light, a lighter amber in dark.
    static let connectAmberText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xFB / 255, green: 0xBF / 255, blue: 0x5A / 255, alpha: 1)
            : UIColor(red: 0xB4 / 255, green: 0x53 / 255, blue: 0x09 / 255, alpha: 1)
    })
}

#Preview {
    ConnectAgentView()
}
