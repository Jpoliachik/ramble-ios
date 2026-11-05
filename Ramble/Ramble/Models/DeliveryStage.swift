//
//  DeliveryStage.swift
//  Ramble
//
//  Where one note is on its way to the agent or webhook, in the words the
//  app uses everywhere: the list row icon, the pill on the note screen and
//  the Home status line. Computed from fields Recording already has.
//

import SwiftUI

enum DeliveryStage: Equatable {
    /// Waiting to transcribe, transcribing, or retrying a transcription.
    case transcribing
    /// Transcription gave up. `needsModel` when the on-device model is missing.
    case couldntTranscribe(needsModel: Bool)
    /// Transcribed, but there was nowhere to send it.
    case onPhone
    case sending
    /// The relay has it; the agent hasn't picked it up yet.
    case waitingForAgent
    case agentHasIt
    /// Webhook only: the webhook accepted it.
    case deliveredToWebhook
    case didntSend

    init(_ recording: Recording) {
        switch recording.status {
        case .recorded, .transcribing:
            self = .transcribing
        case .failed:
            self = .couldntTranscribe(needsModel: recording.isModelNotInstalled)
        case .completed:
            switch recording.deliveryStatus {
            case .pending, .sending: self = .sending
            case .failed: self = .didntSend
            case .none: self = .onPhone
            case .delivered:
                if recording.isWaitingForAgent {
                    self = .waitingForAgent
                } else if recording.relayStatus == .delivered {
                    self = .agentHasIt
                } else {
                    self = .deliveredToWebhook
                }
            }
        }
    }

    /// Short words for pills and row captions.
    var label: String {
        switch self {
        case .transcribing: return "Transcribing…"
        case .couldntTranscribe(let needsModel): return needsModel ? "Needs speech model" : "Couldn't transcribe"
        case .onPhone: return RelayService.shared.hasConnectedAgents ? "On iPhone · not sent" : "On iPhone · no agent"
        case .sending: return "Sending…"
        case .waitingForAgent: return "Waiting for your agent"
        case .agentHasIt: return "Your agent has it"
        case .deliveredToWebhook: return "Delivered to webhook"
        case .didntSend: return "Didn't send"
        }
    }

    var isInProgress: Bool {
        self == .transcribing || self == .sending
    }

    /// Something the person has to look at.
    var needsAttention: Bool {
        switch self {
        case .couldntTranscribe, .didntSend: return true
        default: return false
        }
    }

    var isDone: Bool {
        self == .agentHasIt || self == .deliveredToWebhook
    }

    /// The dot and icon color: green done, amber waiting, red stuck.
    var tint: Color {
        switch self {
        case .transcribing, .sending: return .secondary
        case .onPhone: return .secondary
        case .waitingForAgent: return .brandAmber
        case .agentHasIt, .deliveredToWebhook: return .green
        case .couldntTranscribe(let needsModel): return needsModel ? .brandAmber : .red
        case .didntSend: return .red
        }
    }

    /// Row icon. Nil while in progress, where the row shows a spinner.
    var systemImage: String? {
        switch self {
        case .transcribing, .sending: return nil
        case .onPhone, .waitingForAgent: return "tray"
        case .agentHasIt, .deliveredToWebhook: return "checkmark.circle.fill"
        case .couldntTranscribe(let needsModel): return needsModel ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill"
        case .didntSend: return "exclamationmark.triangle.fill"
        }
    }

    /// Row icon color. Done notes stay quiet so the list isn't a wall of green.
    var iconTint: Color {
        isDone ? Color(.tertiaryLabel) : tint
    }
}

/// The small dot-and-words capsule used on Home and on the note screen.
struct StatusPill: View {
    let text: String
    let dot: Color
    var action: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(Color.primary)
            if let action {
                Text(action)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.brandAmber)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .lineLimit(1)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
