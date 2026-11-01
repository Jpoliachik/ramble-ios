//
//  ConnectAgentView.swift
//  Ramble
//
//  Connect an agent to this phone's relay inbox: pick a provider (skipped
//  while only one is offered), hand the agent a single-use pairing code, and
//  manage existing connections.
//

import SwiftUI

struct ConnectAgentView: View {
    /// When set, a pairing code for this agent is requested as soon as the
    /// view appears, skipping the picker. Settings passes the only pickable
    /// agent here for its "Connect Muse" entry.
    var startPairingWith: RelayAgent? = nil

    @ObservedObject private var relay = RelayService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pairCode: RelayPairCode?
    @State private var requestingAgent: RelayAgent?
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var pairingNote: String?
    @State private var didAutoStart = false

    @State private var connectionToDisconnect: RelayConnection?
    @State private var showDeleteQueuedConfirmation = false
    @State private var isDeletingQueued = false
    @State private var deleteQueuedResult: String?

    @State private var copiedCode = false
    @State private var copiedMessage = false

    var body: some View {
        NavigationStack {
            Form {
                if !relay.isConfigured {
                    Section {
                        Text("The Ramble relay isn't available in this build yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !relay.connections.isEmpty {
                        connectionsSection
                    }
                    if let pairCode {
                        pairCodeSection(pairCode)
                    } else {
                        pickerSection
                    }
                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(Color.brandRed)
                        }
                    }
                }
                privacySection
            }
            .navigationTitle(Self.connectTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if relay.isConfigured {
                        Button {
                            refresh()
                        } label: {
                            if isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshing)
                        .accessibilityLabel("Refresh")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard relay.isConfigured else { return }
                if let agent = startPairingWith, !didAutoStart, pairCode == nil {
                    didAutoStart = true
                    requestCode(for: agent)
                }
                await loadConnections()
            }
            .confirmationDialog(
                "Disconnect \(connectionToDisconnect?.agentType.displayName ?? "agent")?",
                isPresented: Binding(
                    get: { connectionToDisconnect != nil },
                    set: { if !$0 { connectionToDisconnect = nil } }
                ),
                titleVisibility: .visible,
                presenting: connectionToDisconnect
            ) { connection in
                Button("Disconnect", role: .destructive) {
                    disconnect(connection)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The agent loses access immediately. Anything waiting for it is deleted.")
            }
            .confirmationDialog(
                "Delete everything waiting?",
                isPresented: $showDeleteQueuedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteQueued()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Transcripts your agents haven't picked up yet are deleted from the relay. Your agents stay connected, and the copies on this phone stay.")
            }
        }
    }

    // MARK: - Sections

    private var connectionsSection: some View {
        Section {
            ForEach(relay.connections) { connection in
                HStack(spacing: 12) {
                    AgentConnectionRow(connection: connection)
                    Button("Disconnect") {
                        connectionToDisconnect = connection
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.brandRed)
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Connected")
        }
    }

    @ViewBuilder
    private var pickerSection: some View {
        if let only = Self.onlyAgent {
            singleAgentSection(only)
        } else {
            multiAgentPickerSection
        }
    }

    /// One provider on offer: no picker, just a button to get a code.
    private func singleAgentSection(_ agent: RelayAgent) -> some View {
        Section {
            Button {
                requestCode(for: agent)
            } label: {
                HStack(spacing: 12) {
                    AgentIcon(agent: agent)
                    Text("Get a pairing code for \(agent.displayName)")
                        .foregroundStyle(Color.obInk)
                    Spacer()
                    if requestingAgent == agent {
                        ProgressView()
                    }
                }
            }
            .disabled(requestingAgent != nil)
        } footer: {
            Text("Ramble gives you a pairing code. Send it to \(agent.displayName) and it connects itself.")
        }
    }

    private var multiAgentPickerSection: some View {
        Section {
            ForEach(RelayAgent.pickable) { agent in
                Button {
                    requestCode(for: agent)
                } label: {
                    HStack(spacing: 12) {
                        AgentIcon(agent: agent)
                        Text(agent.displayName)
                            .foregroundStyle(Color.obInk)
                        Spacer()
                        if requestingAgent == agent {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.obInkFaint)
                        }
                    }
                }
                .disabled(requestingAgent != nil)
            }
        } header: {
            Text(relay.connections.isEmpty ? "Choose your agent" : "Connect another")
        } footer: {
            Text("Ramble gives you a pairing code. Paste it into your agent and it connects itself.")
        }
    }

    private func pairCodeSection(_ code: RelayPairCode) -> some View {
        Section {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    AgentIcon(agent: code.agentType)
                    Text("Pairing code for \(code.agentType.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(Color.obInkSoft)
                }

                Text(code.code)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.obInk)
                    .textSelection(.enabled)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                PairCodeCountdown(expiresAt: code.expiresAt)

                Button {
                    copy(code.code)
                    flash($copiedCode)
                } label: {
                    Label(copiedCode ? "Copied" : "Copy code", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandRed)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Tell \(code.agentType.displayName):")
                    .font(.subheadline)
                    .foregroundStyle(Color.obInkSoft)
                Text(suggestedMessage(for: code))
                    .font(.body)
                    .foregroundStyle(Color.obInk)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                HStack(spacing: 16) {
                    Button {
                        copy(suggestedMessage(for: code))
                        flash($copiedMessage)
                    } label: {
                        Label(copiedMessage ? "Copied" : "Copy message", systemImage: copiedMessage ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    ShareLink(item: suggestedMessage(for: code)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 4)

            if let pairingNote {
                Text(pairingNote)
                    .font(.subheadline)
                    .foregroundStyle(Color.obInkSoft)
            }

            Button {
                checkPairing(for: code.agentType)
            } label: {
                HStack {
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Text("Done, I've sent it")
                    }
                    Spacer()
                }
            }
            .disabled(isRefreshing)

            Button(Self.onlyAgent == nil ? "Choose a different agent" : "Get a new code") {
                if Self.onlyAgent == nil {
                    pairCode = nil
                    pairingNote = nil
                    errorMessage = nil
                } else {
                    requestCode(for: code.agentType)
                }
            }
            .disabled(requestingAgent != nil)
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.secondary)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("The code works once and expires in 10 minutes, so it's safe to paste into chat.")
                if let note = Self.scheduleNote(for: code.agentType) {
                    Text(note)
                }
            }
        }
    }

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcripts wait on the Ramble relay until your agent picks them up. The text is deleted the moment it does. Anything never picked up is deleted after \(Constants.Relay.unclaimedRetentionDays) days.")
                Text("Audio never leaves your phone.")
                Text("No accounts. The relay knows this inbox, not you.")
                Text("Each agent can read only this phone's transcripts and can't do anything else.")
            }
            .font(.subheadline)
            .foregroundStyle(Color.obInkSoft)
            .padding(.vertical, 4)

            if relay.isConfigured {
                Button(role: .destructive) {
                    showDeleteQueuedConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        if isDeletingQueued {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Delete everything waiting now")
                        Spacer()
                    }
                    .foregroundStyle(Color.brandRed)
                }
                .disabled(isDeletingQueued)

                if let deleteQueuedResult {
                    Text(deleteQueuedResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - Actions

    private func suggestedMessage(for code: RelayPairCode) -> String {
        "I downloaded Ramble, connect it. My pairing code is \(code.code)."
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
        HapticService.success()
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            flag.wrappedValue = false
        }
    }

    private func loadConnections() async {
        guard relay.hasInbox else { return }
        do {
            try await relay.refreshConnections()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Agent-specific setup copy. Nil when there's nothing to add.
    static func scheduleNote(for agent: RelayAgent) -> String? {
        switch agent {
        case .muse:
            return "Muse checks for new thoughts on a schedule, so expect minutes, not seconds."
        default:
            return nil
        }
    }

    /// The single agent on offer, when there's only one.
    static var onlyAgent: RelayAgent? {
        RelayAgent.pickable.count == 1 ? RelayAgent.pickable.first : nil
    }

    /// "Connect Muse" while Muse is the only option, else "Connect an agent".
    static var connectTitle: String {
        if let only = onlyAgent { return "Connect \(only.displayName)" }
        return "Connect an agent"
    }

    /// "Done, I've sent it": refresh, and clear the code once the agent shows up.
    private func checkPairing(for agent: RelayAgent) {
        let before = relay.connections.filter { $0.agentType == agent }.count
        isRefreshing = true
        pairingNote = nil
        Task {
            do {
                let list = try await relay.refreshConnections()
                errorMessage = nil
                if list.filter({ $0.agentType == agent }).count > before {
                    pairCode = nil
                } else {
                    pairingNote = "\(agent.displayName) hasn't used the code yet. Once it does, it shows up here."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    private func refresh() {
        isRefreshing = true
        Task {
            do {
                try await relay.refreshConnections()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    private func requestCode(for agent: RelayAgent) {
        requestingAgent = agent
        errorMessage = nil
        pairingNote = nil
        Task {
            do {
                pairCode = try await relay.createPairCode(for: agent)
                copiedCode = false
                copiedMessage = false
            } catch {
                errorMessage = error.localizedDescription
            }
            requestingAgent = nil
        }
    }

    private func disconnect(_ connection: RelayConnection) {
        errorMessage = nil
        Task {
            do {
                try await relay.disconnect(connection)
                HapticService.success()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteQueued() {
        isDeletingQueued = true
        deleteQueuedResult = nil
        errorMessage = nil
        Task {
            do {
                let count = try await relay.deleteAllQueued()
                deleteQueuedResult = count == 0
                    ? "Nothing was waiting."
                    : "Deleted \(count) \(count == 1 ? "transcript" : "transcripts")."
                HapticService.success()
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeletingQueued = false
        }
    }
}

// MARK: - Components

/// Agent glyph in a small rounded tile.
struct AgentIcon: View {
    let agent: RelayAgent

    var body: some View {
        Image(systemName: agent.iconName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.obInk)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
            )
    }
}

/// Name, last check, and pending count for one connected agent.
struct AgentConnectionRow: View {
    let connection: RelayConnection

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(agent: connection.agentType)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.agentType.displayName)
                    .font(.body)
                    .foregroundStyle(Color.obInk)
                Text(Self.statusText(for: connection))
                    .font(.caption)
                    .foregroundStyle(Color.obInkFaint)
            }
            Spacer(minLength: 0)
        }
    }

    static func statusText(for connection: RelayConnection) -> String {
        var parts: [String] = []
        if let lastPull = connection.lastPullAt {
            parts.append("Last checked \(relativeFormatter.localizedString(for: lastPull, relativeTo: Date()))")
        } else {
            parts.append("Waiting for first check")
        }
        if connection.pending > 0 {
            parts.append("\(connection.pending) waiting")
        }
        return parts.joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

/// Live "Expires in 9:41" countdown for a pairing code.
private struct PairCodeCountdown: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date).rounded(.up)))
            if remaining > 0 {
                Text("Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.obInkFaint)
            } else {
                Text("Expired. Get a new code to try again.")
                    .font(.subheadline)
                    .foregroundStyle(Color.brandRed)
            }
        }
    }
}

#Preview {
    ConnectAgentView()
}
