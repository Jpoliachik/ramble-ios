//
//  ConnectAgentView.swift
//  Ramble
//
//  Connect an agent to this phone's relay inbox by handing it a single-use
//  pairing code, and manage the agents already connected.
//

import SwiftUI

struct ConnectAgentView: View {
    @ObservedObject private var relay = RelayService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pairCode: RelayPairCode?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var note: String?
    @State private var connectionToDisconnect: RelayConnection?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
<<<<<<< HEAD
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
                                .foregroundStyle(Color.brandAmber)
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
=======
                if !relay.connections.isEmpty {
                    Section("Connected") {
                        ForEach(relay.connections) { connection in
                            HStack {
                                AgentConnectionRow(connection: connection)
                                Button("Disconnect") { connectionToDisconnect = connection }
                                    .font(.subheadline)
                                    .foregroundStyle(Color.brandAmber)
                                    .buttonStyle(.borderless)
>>>>>>> origin/claude/project-thread-mopb4y
                            }
                        }
                    }
                }

                if let pairCode {
                    pairCodeSection(pairCode)
                } else {
                    Section {
                        Button {
                            requestCode()
                        } label: {
                            HStack {
                                Text("Get a pairing code")
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(isWorking)
                    } footer: {
                        Text("Send the code to your agent and it connects itself.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Color.brandAmber)
                    }
                }

                privacySection
            }
            .navigationTitle("Connect your agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await run { try await relay.refreshConnections() } }
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
                "Delete everything waiting?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
<<<<<<< HEAD
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
                    .foregroundStyle(Color.brandAmber)
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
=======
                    Task {
                        await run {
                            let count = try await relay.deleteAllWaiting()
                            note = count == 0 ? "Nothing was waiting." : "Deleted \(count) waiting."
>>>>>>> origin/claude/project-thread-mopb4y
                        }
                    }
                }
            } message: {
                Text("Transcripts your agent hasn't picked up are deleted from the relay. Your agent stays connected, and the copies on this phone stay.")
            }
        }
    }

    private func pairCodeSection(_ code: RelayPairCode) -> some View {
        Section {
            VStack(spacing: 12) {
                Text(code.code)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                PairCodeCountdown(expiresAt: code.expiresAt)
                Button {
                    UIPasteboard.general.string = message(for: code)
                    HapticService.success()
                } label: {
                    Label("Copy message", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAmber)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Text(message(for: code))
                .font(.subheadline)
                .foregroundStyle(Color.obInkSoft)
                .textSelection(.enabled)

            Button("Done, I've sent it") { checkPairing() }
                .disabled(isWorking)
            Button("Get a new code") { requestCode() }
                .disabled(isWorking)

            if let note {
                Text(note).font(.subheadline).foregroundStyle(Color.obInkSoft)
            }
        } footer: {
            Text("The code works once and expires in 10 minutes, so it's safe to paste into chat.")
        }
    }

    private var privacySection: some View {
<<<<<<< HEAD
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
                    .foregroundStyle(Color.brandAmber)
                }
                .disabled(isDeletingQueued)

                if let deleteQueuedResult {
                    Text(deleteQueuedResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
=======
        Section("Privacy") {
            Text("Transcripts wait on the Ramble relay until your agent picks them up, and are deleted the moment it does. Anything never picked up is deleted after \(Constants.Relay.unclaimedRetentionDays) days. Audio never leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(Color.obInkSoft)
            if relay.hasInbox {
                Button("Delete everything waiting now", role: .destructive) {
                    showDeleteConfirmation = true
>>>>>>> origin/claude/project-thread-mopb4y
                }
                .disabled(isWorking)
            }
            if pairCode == nil, let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func message(for code: RelayPairCode) -> String {
        "I downloaded Ramble, connect it. My pairing code is \(code.code)."
    }

    private func requestCode() {
        note = nil
        Task { await run { pairCode = try await relay.createPairCode() } }
    }

    /// Refresh, and clear the code once a new agent shows up.
    private func checkPairing() {
        let before = relay.connections.count
        note = nil
        Task {
            await run {
                if try await relay.refreshConnections().count > before {
                    pairCode = nil
                    HapticService.success()
                } else {
                    note = "Your agent hasn't used the code yet. Once it does, it shows up here."
                }
            }
        }
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do { try await action() } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }
}

/// When a connected agent last checked in, and how much is waiting for it.
struct AgentConnectionRow: View {
    let connection: RelayConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Agent")
                .foregroundStyle(Color.obInk)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(Color.obInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        var parts = [connection.lastPullAt.map {
            "Last checked \($0.formatted(.relative(presentation: .named)))"
        } ?? "Hasn't checked in yet"]
        if connection.pending > 0 { parts.append("\(connection.pending) waiting") }
        return parts.joined(separator: " · ")
    }
}

/// Live "Expires in 9:41" countdown for a pairing code.
private struct PairCodeCountdown: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date).rounded(.up)))
<<<<<<< HEAD
            if remaining > 0 {
                Text("Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.obInkFaint)
            } else {
                Text("Expired. Get a new code to try again.")
                    .font(.subheadline)
                    .foregroundStyle(Color.brandAmber)
            }
=======
            Text(remaining > 0
                 ? "Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                 : "Expired. Get a new code.")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(remaining > 0 ? Color.obInkFaint : Color.brandAmber)
>>>>>>> origin/claude/project-thread-mopb4y
        }
    }
}

#Preview {
    ConnectAgentView()
}
