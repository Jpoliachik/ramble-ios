//
//  HomeStatusLine.swift
//  Ramble
//
//  The one line under the Home title (specs/phone.md "Status line shows the
//  single worst state"). Pills ask for the person and open their fix;
//  quiet states are plain text. Built from what the app already knows.
//

import SwiftUI

enum HomeStatus: Equatable {
    case didntSend(count: Int)
    case toUnlock(count: Int)
    case noAgent
    case freeNotesLow(remaining: Int)
    case agentQuiet(lastCheckIn: Date?)
    case waitingLong(count: Int)
    case sending(count: Int)
    case transcribing(count: Int)
    case waiting(count: Int)
    case checking
    case allGood(lastCheckIn: Date?)

    /// Notes waiting longer than this raise a pill.
    static let longWait: TimeInterval = 12 * 3600

    static func compute(
        recordings: [Recording],
        connections: [RelayConnection],
        hasAgent: Bool,
        hasWebhook: Bool,
        account: RelayAccount?,
        now: Date = Date()
    ) -> HomeStatus {
        let stages = recordings.map { ($0, DeliveryStage($0, hasAgents: hasAgent)) }
        func count(_ stage: DeliveryStage) -> Int { stages.filter { $0.1 == stage }.count }

        let failed = count(.didntSend)
        if failed > 0 { return .didntSend(count: failed) }

        let held = count(.heldForUnlock)
        if held > 0 { return .toUnlock(count: held) }

        if !hasAgent && !hasWebhook { return .noAgent }

        if let account, !account.unlocked, account.freeNotesRemaining <= 5 {
            return .freeNotesLow(remaining: account.freeNotesRemaining)
        }

        let waiting = stages.filter { $0.1 == .waitingForAgent }.map(\.0)
        let lastCheckIn = connections.compactMap(\.lastPullAt).max()
        if hasAgent, let oldest = waiting.map(\.waitingSince).min(), now.timeIntervalSince(oldest) > longWait {
            if let lastCheckIn, now.timeIntervalSince(lastCheckIn) < longWait {
                let long = waiting.filter { now.timeIntervalSince($0.waitingSince) > longWait }.count
                return .waitingLong(count: long)
            }
            return .agentQuiet(lastCheckIn: lastCheckIn)
        }

        let sending = stages.filter { $0.1.isNotYetAccepted }.count
        if sending > 0 { return .sending(count: sending) }

        let transcribing = count(.transcribing)
        if transcribing > 0 { return .transcribing(count: transcribing) }

        if !waiting.isEmpty { return .waiting(count: waiting.count) }

        if count(.checkingDelivery) > 0 { return .checking }

        return .allGood(lastCheckIn: hasAgent ? lastCheckIn : nil)
    }

    /// Pills ask for attention and stay put on scroll; quiet lines don't.
    var isPill: Bool {
        switch self {
        case .didntSend, .toUnlock, .noAgent, .freeNotesLow, .agentQuiet, .waitingLong: return true
        case .sending, .transcribing, .waiting, .checking, .allGood: return false
        }
    }
}

struct HomeStatusLine: View {
    let status: HomeStatus
    let isEmptyList: Bool
    let hasAgent: Bool
    let onTap: () -> Void

    var body: some View {
        Group {
            if status.isPill {
                Button {
                    HapticService.buttonTap()
                    onTap()
                } label: {
                    StatusPill(text: text, dot: dot, action: action, actionColor: actionColor)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 7) {
                    switch status {
                    case .sending, .transcribing, .checking:
                        ProgressView().controlSize(.mini)
                    default:
                        Circle().fill(dot).frame(width: 8, height: 8)
                    }
                    Text(text)
                        .foregroundStyle(Color.secondary)
                }
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: String {
        switch status {
        case .didntSend(let count):
            return count == 1 ? "1 note didn't send" : "\(count) notes didn't send"
        case .toUnlock(let count):
            return count == 1 ? "1 note to unlock" : "\(count) notes to unlock"
        case .noAgent:
            return "No agent connected"
        case .freeNotesLow(let remaining):
            return remaining == 1 ? "1 free note left" : "\(remaining) free notes left"
        case .agentQuiet(let lastCheckIn):
            guard let lastCheckIn else { return "Your agent hasn't checked in" }
            return "Your agent hasn't checked in · \(Self.age(since: lastCheckIn))"
        case .waitingLong(let count):
            return count == 1 ? "1 note waiting for your agent" : "\(count) notes waiting for your agent"
        case .sending(let count):
            return count == 1 ? "Sending 1 note…" : "Sending \(count) notes…"
        case .transcribing(let count):
            return count == 1 ? "Transcribing 1 note…" : "Transcribing \(count) notes…"
        case .waiting(let count):
            return "\(count) waiting for your agent"
        case .checking:
            return "Checking delivery…"
        case .allGood(let lastCheckIn):
            if isEmptyList {
                return hasAgent ? "Your agent is connected" : "Sending to your webhook"
            }
            guard let lastCheckIn else { return "All delivered" }
            let age = Self.age(since: lastCheckIn)
            return "All delivered · checked in \(age == "now" ? "just now" : "\(age) ago")"
        }
    }

    private var action: String? {
        switch status {
        case .didntSend: return "Fix"
        case .toUnlock, .freeNotesLow: return "Unlock"
        case .noAgent: return "Connect"
        default: return nil
        }
    }

    private var actionColor: Color {
        if case .didntSend = status { return .red }
        return .brandAmber
    }

    private var dot: Color {
        switch status {
        case .didntSend: return .red
        case .toUnlock, .noAgent, .freeNotesLow, .agentQuiet, .waitingLong: return .brandAmber
        case .waiting: return .secondary
        case .sending, .transcribing, .checking, .allGood: return .green
        }
    }

    /// "now", "5m", "14h", "3d".
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HomeStatusLine(status: .allGood(lastCheckIn: Date().addingTimeInterval(-120)), isEmptyList: false, hasAgent: true) {}
        HomeStatusLine(status: .transcribing(count: 2), isEmptyList: false, hasAgent: true) {}
        HomeStatusLine(status: .noAgent, isEmptyList: true, hasAgent: false) {}
        HomeStatusLine(status: .toUnlock(count: 2), isEmptyList: false, hasAgent: true) {}
        HomeStatusLine(status: .didntSend(count: 2), isEmptyList: false, hasAgent: true) {}
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
