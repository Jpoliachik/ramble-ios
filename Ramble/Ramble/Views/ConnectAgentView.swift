//
//  ConnectAgentView.swift
//  Ramble
//
//  Connect an agent to this phone's relay inbox by handing it a single-use
//  pairing code, and manage the agents already connected.
//
//  One job per screen: pairing shows the message to send and waits for the
//  agent on its own; once an agent is connected the same sheet becomes the
//  place to manage it, along with the relay's privacy controls.
//

import SwiftUI

struct ConnectAgentView: View {
    @ObservedObject private var relay = RelayService.shared
    @Environment(\.dismiss) private var dismiss

    /// Opens straight onto a new code, e.g. from "Connect another agent".
    private let startPairing: Bool

    /// Pairing vs. managing. Starts from the cached connection count so the
    /// sheet opens on the right screen before the first refresh lands.
    @State private var isPairing: Bool
    @State private var pairCode: RelayPairCode?
    /// Connections when the current code was issued; more than this means it was used.
    @State private var baselineCount = 0
    @State private var hasSent = false
    @State private var justCopied = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var note: String?
    @State private var connectionToDisconnect: RelayConnection?
    @State private var showDeleteConfirmation = false

    private static let pollInterval: Duration = .seconds(4)

    init(startPairing: Bool = false) {
        self.startPairing = startPairing
        _isPairing = State(initialValue: startPairing || !RelayService.shared.hasConnectedAgents)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isPairing {
                    pairingScreen
                } else {
                    connectedScreen
                }
            }
            .animation(.smooth, value: isPairing)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if isPairing && !relay.connections.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back", systemImage: "chevron.backward") {
                            pairCode = nil
                            isPairing = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task { await loadConnections() }
            .onChange(of: relay.connections.isEmpty) { _, isEmpty in
                if isEmpty { isPairing = true }
            }
            .confirmationDialog(
                "Disconnect this agent?",
                isPresented: Binding(
                    get: { connectionToDisconnect != nil },
                    set: { if !$0 { connectionToDisconnect = nil } }
                ),
                titleVisibility: .visible,
                presenting: connectionToDisconnect
            ) { connection in
                Button("Disconnect", role: .destructive) {
                    Task { await run { try await relay.disconnect(connection) } }
                }
            } message: { _ in
                Text("It loses access immediately, and anything waiting for it is deleted.")
            }
            .confirmationDialog(
                "Delete waiting transcripts?",
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
                Text("Transcripts your agent hasn't picked up are deleted from the relay. Your agent stays connected, and the copies on this phone stay.")
            }
        }
    }

    // MARK: - Pairing

    private var pairingScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Send this to\nyour agent")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("Paste it into a chat with your agent. It connects itself.")
                        .font(.body)
                        .foregroundStyle(Color.obInkSoft)
                }
                .padding(.top, 8)

                MessageBubble(code: pairCode?.code)
                    .padding(.top, 28)

                codeMeta
                    .padding(.top, 12)
                    .padding(.horizontal, 4)

                if hasSent, let pairCode, pairCode.expiresAt > .now {
                    WaitingCard()
                        .padding(.top, 22)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let errorMessage {
                    ErrorLabel(text: errorMessage)
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, 20)
            .animation(.smooth, value: hasSent)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { pairingActions }
        .task { if pairCode == nil { requestCode() } }
        .task(id: pairCode?.code) { await waitForAgent() }
    }

    private var codeMeta: some View {
        HStack {
            if let pairCode {
                PairCodeCountdown(expiresAt: pairCode.expiresAt)
            } else if isWorking {
                Text("Getting a code…")
                    .font(.footnote)
                    .foregroundStyle(Color.obInkFaint)
            }
            Spacer()
            Button {
                requestCode()
            } label: {
                Label("New code", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.obInkSoft)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }

    private var pairingActions: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    copyMessage()
                } label: {
                    Label(justCopied ? "Copied" : "Copy message",
                          systemImage: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(justCopied ? Color.obInk : Color.onConnectAmber)
                        .background(justCopied ? Color(.tertiarySystemFill) : Color.brandAmber,
                                    in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(pairCode == nil)

                if let pairCode {
                    ShareLink(item: message(for: pairCode.code)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.obInk)
                            .frame(width: 54, height: 54)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .simultaneousGesture(TapGesture().onEnded { hasSent = true })
                    .accessibilityLabel("Share message")
                }
            }

            Label("The code works once, so it's safe to paste into chat.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Color.obInkFaint)
                .labelStyle(FootnoteLabelStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Connected

    private var connectedScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.brandAmber)
                    .frame(width: 64, height: 64)
                    .background(Color.brandAmberSoft, in: Circle())
                    .padding(.top, 8)

                Text(relay.connections.count > 1 ? "Your agents are\nconnected" : "Your agent is\nconnected")
                    .font(.system(.largeTitle, weight: .bold))
                    .padding(.top, 18)
                Text("Talk to your watch and move on. Your agent picks it up next time it checks.")
                    .font(.body)
                    .foregroundStyle(Color.obInkSoft)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(relay.connections.enumerated()), id: \.element.id) { index, connection in
                        if index > 0 { Divider().padding(.leading, 64) }
                        ConnectedAgentCell(connection: connection) {
                            connectionToDisconnect = connection
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 24)

                privacyCard
                    .padding(.top, 26)

                if let errorMessage {
                    ErrorLabel(text: errorMessage)
                        .padding(.top, 18)
                }

                Button {
                    note = nil
                    isPairing = true
                } label: {
                    Label("Connect another agent", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.connectAmberText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await run { try await relay.refreshConnections() } }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Temporary by design", systemImage: "lock.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.obInkFaint)
                .labelStyle(FootnoteLabelStyle())
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text("Transcripts wait on the relay until your agent picks them up, then they're deleted. Anything left is deleted after \(Constants.Relay.unclaimedRetentionDays) days. Audio stays on your phone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.obInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)

                if relay.hasInbox {
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Text("Delete waiting transcripts")
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
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isWorking)
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Actions

    private func message(for code: String) -> String {
        "I downloaded Ramble, connect it. My pairing code is \(code). Instructions: https://ramble.watch/docs"
    }

    private func copyMessage() {
        guard let pairCode else { return }
        UIPasteboard.general.string = message(for: pairCode.code)
        HapticService.success()
        hasSent = true
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }

    private func requestCode() {
        hasSent = false
        Task {
            await run {
                baselineCount = relay.connections.count
                pairCode = try await relay.createPairCode()
            }
        }
    }

    private func loadConnections() async {
        await run { try await relay.refreshConnections() }
        if !startPairing && !relay.connections.isEmpty && pairCode == nil { isPairing = false }
    }

    /// Checks the relay every few seconds while a live code is on screen and
    /// flips to the connected screen once a new agent shows up. Errors here
    /// stay quiet; the next tick retries.
    private func waitForAgent() async {
        guard let code = pairCode else { return }
        while !Task.isCancelled, code.expiresAt > .now {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled,
                  let list = try? await relay.refreshConnections(),
                  list.count > baselineCount
            else { continue }
            HapticService.success()
            pairCode = nil
            hasSent = false
            isPairing = false
            return
        }
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do { try await action() } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }
}

// MARK: - Pieces

/// The message the user is about to send, drawn as their own chat bubble with
/// the code picked out. Shows a placeholder while the code loads.
private struct MessageBubble: View {
    let code: String?

    var body: some View {
        HStack {
            Spacer(minLength: 32)
            Text(attributed)
                .font(.body)
                .foregroundStyle(Color.obInk)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    Color.brandAmberSoft,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 22, bottomLeadingRadius: 22,
                        bottomTrailingRadius: 6, topTrailingRadius: 22,
                        style: .continuous
                    )
                )
                .redacted(reason: code == nil ? .placeholder : [])
        }
    }

    private var attributed: AttributedString {
        var text = AttributedString("I downloaded Ramble, connect it. My pairing code is ")
        var codePart = AttributedString(code ?? "XXXX-XXXX")
        codePart.swiftUI.font = Font.body.monospaced().weight(.semibold)
        codePart.swiftUI.foregroundColor = Color.connectAmberText
        var link = AttributedString("ramble.watch/docs")
        link.swiftUI.underlineStyle = Text.LineStyle(pattern: .solid)
        link.swiftUI.foregroundColor = Color.obInkSoft
        text += codePart
        text += AttributedString(". Instructions: ")
        text += link
        return text
    }
}

private struct WaitingCard: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.brandAmber)
                .frame(width: 10, height: 10)
                .background(
                    Circle()
                        .fill(Color.brandAmber.opacity(0.25))
                        .scaleEffect(pulsing ? 2.4 : 1)
                        .opacity(pulsing ? 0 : 1)
                )
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for your agent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.obInk)
                Text("This screen updates when it connects.")
                    .font(.footnote)
                    .foregroundStyle(Color.obInkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

private struct ErrorLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(Color.connectAmberText)
    }
}

/// Small icon tucked against the first line of footnote text.
private struct FootnoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// When a connected agent last checked in, and how much is waiting for it.
struct AgentConnectionRow: View {
    let connection: RelayConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Agent")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.obInk)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(Color.obInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        let checked = connection.lastPullAt.map {
            "Checked \($0.formatted(.relative(presentation: .named)))"
        } ?? "Hasn't checked in yet"
        return "\(checked) · \(connection.pending) waiting"
    }
}

/// A connected agent on the manage screen, with a menu to disconnect it.
private struct ConnectedAgentCell: View {
    let connection: RelayConnection
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brandAmber)
                .frame(width: 36, height: 36)
                .background(Color.brandAmberSoft,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            AgentConnectionRow(connection: connection)
            Menu {
                Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: onDisconnect)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.obInkFaint)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Agent options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Live "Expires in 9:41" countdown for a pairing code.
private struct PairCodeCountdown: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date).rounded(.up)))
            Text(remaining > 0
                 ? "Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                 : "Expired. Get a new code.")
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(remaining > 0 ? Color.obInkFaint : Color.connectAmberText)
        }
    }
}

private extension Color {
    /// Brand amber for text: #b45309 in light, a lighter amber in dark so it
    /// stays readable on the soft amber bubble.
    static let connectAmberText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xFB / 255, green: 0xBF / 255, blue: 0x5A / 255, alpha: 1)
            : UIColor(red: 0xB4 / 255, green: 0x53 / 255, blue: 0x09 / 255, alpha: 1)
    })

    /// Label color on a filled amber button. White doesn't have enough
    /// contrast on the bright dark-mode amber, so dark mode uses near-black.
    static let onConnectAmber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1F / 255, green: 0x14 / 255, blue: 0x04 / 255, alpha: 1)
            : .white
    })
}

#Preview {
    ConnectAgentView()
}
