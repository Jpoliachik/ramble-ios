//
//  HomeStatusLine.swift
//  Ramble
//
//  The one line under the Home title, shown whether the list is empty or
//  full. When everything works it says so quietly; when something needs
//  the person it becomes a pill they can tap. Only the worst state shows.
//
//  Built from what the app already knows (recordings, the cached relay
//  connections, the webhook setting). It refreshes when Home opens and when
//  the app comes back to the foreground, with no polling of its own.
//

import SwiftUI

enum HomeStatus: Equatable {
    /// Notes that failed to transcribe or send.
    case didntSend(count: Int)
    case noAgent
    /// Notes have waited past the alert threshold and the agent hasn't
    /// checked in since before then.
    case agentQuiet(lastCheckIn: Date?)
    /// Notes have waited past the threshold, but the agent is checking in.
    case waitingLong(count: Int)
    /// Transcribed notes that were never sent anywhere.
    case notSent(count: Int)
    case working(count: Int)
    case waiting(count: Int)
    case allGood(lastCheckIn: Date?)

    @MainActor
    static func compute(
        recordings: [Recording],
        connections: [RelayConnection],
        hasAgent: Bool,
        hasWebhook: Bool,
        now: Date = Date()
    ) -> HomeStatus {
        let stages = recordings.map(DeliveryStage.init)

        let stuck = stages.filter(\.needsAttention).count
        if stuck > 0 { return .didntSend(count: stuck) }

        if !hasAgent && !hasWebhook { return .noAgent }

        // Same "not picked up" threshold the delivery alerts use.
        let threshold = DeliveryMonitor.rule(for: .notPickedUp).threshold
        let waitingSince = recordings
            .filter(\.isWaitingForAgent)
            .compactMap(\.relayUploadedAt)
            .filter { now.timeIntervalSince($0) < RelayQueueService.relayRetention }
        let lastCheckIn = connections.compactMap(\.lastPullAt).max()

        if hasAgent, let oldest = waitingSince.min(), now.timeIntervalSince(oldest) > threshold {
            if let lastCheckIn, now.timeIntervalSince(lastCheckIn) < threshold {
                return .waitingLong(count: waitingSince.count)
            }
            return .agentQuiet(lastCheckIn: lastCheckIn)
        }

        let notSent = stages.filter { $0 == .onPhone }.count
        if notSent > 0 { return .notSent(count: notSent) }

        let working = stages.filter(\.isInProgress).count
        if working > 0 { return .working(count: working) }

        if !waitingSince.isEmpty { return .waiting(count: waitingSince.count) }

        return .allGood(lastCheckIn: hasAgent ? lastCheckIn : nil)
    }

    /// Pills ask for attention and stay put on scroll; quiet lines don't.
    var isPill: Bool {
        switch self {
        case .didntSend, .noAgent, .agentQuiet, .waitingLong, .notSent: return true
        case .working, .waiting, .allGood: return false
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
                    StatusPill(text: text, dot: dot, action: action)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 7) {
                    if case .working = status {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle().fill(dot).frame(width: 8, height: 8)
                    }
                    Text(text)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
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
        case .noAgent:
            return "No agent connected"
        case .agentQuiet(let lastCheckIn):
            guard let lastCheckIn else { return "Your agent hasn't checked in" }
            return "Your agent hasn't checked in · \(Self.age(since: lastCheckIn))"
        case .waitingLong(let count):
            return count == 1 ? "1 note waiting for your agent" : "\(count) notes waiting for your agent"
        case .notSent(let count):
            return count == 1 ? "1 note not sent" : "\(count) notes not sent"
        case .working(let count):
            return count == 1 ? "Sending 1 note…" : "Sending \(count) notes…"
        case .waiting(let count):
            return "\(count) waiting for your agent"
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
        case .didntSend, .notSent: return "Fix"
        case .noAgent: return "Connect"
        default: return nil
        }
    }

    private var dot: Color {
        switch status {
        case .didntSend: return .red
        case .noAgent, .agentQuiet, .waitingLong, .notSent, .waiting: return .brandAmber
        case .working, .allGood: return .green
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
        HomeStatusLine(status: .working(count: 2), isEmptyList: false, hasAgent: true) {}
        HomeStatusLine(status: .noAgent, isEmptyList: true, hasAgent: false) {}
        HomeStatusLine(status: .agentQuiet(lastCheckIn: Date().addingTimeInterval(-50_000)), isEmptyList: false, hasAgent: true) {}
        HomeStatusLine(status: .didntSend(count: 2), isEmptyList: false, hasAgent: true) {}
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
