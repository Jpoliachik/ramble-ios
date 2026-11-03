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
                if !relay.connections.isEmpty {
                    Section("Connected") {
                        ForEach(relay.connections) { connection in
                            HStack {
                                AgentConnectionRow(connection: connection)
                                Button("Disconnect") { connectionToDisconnect = connection }
                                    .font(.subheadline)
                                    .foregroundStyle(Color.brandAmber)
                                    .buttonStyle(.borderless)
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
        Section("Privacy") {
            Text("Transcripts wait on the Ramble relay until your agent picks them up, and are deleted the moment it does. Anything never picked up is deleted after \(Constants.Relay.unclaimedRetentionDays) days. Audio never leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(Color.obInkSoft)
            if relay.hasInbox {
                Button("Delete everything waiting now", role: .destructive) {
                    showDeleteConfirmation = true
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
            Text(remaining > 0
                 ? "Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                 : "Expired. Get a new code.")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(remaining > 0 ? Color.obInkFaint : Color.brandAmber)
        }
    }
}

#Preview {
    ConnectAgentView()
}
