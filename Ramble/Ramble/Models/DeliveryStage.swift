//
//  DeliveryStage.swift
//  Ramble
//
//  Where one note is, in the words the app uses everywhere: the list row
//  caption and icon, the pill on the note screen and the Home status line
//  (specs/phone.md "Row states", specs/delivery.md "Delivery states").
//

import SwiftUI

enum DeliveryStage: Equatable {
    /// Phone note not accepted by the server yet.
    case waitingToSend
    /// Watch note the server hasn't accepted yet.
    case waitingOnWatch
    case transcribing
    case heldForUnlock
    case heldForFairUse
    case tooLong
    case couldntSend
    case couldntTranscribe
    case noSpeech
    /// No eligible agent and no webhook.
    case noAgent
    case webhookSending
    case didntSend
    case waitingForAgent
    /// Every agent copy was removed unread.
    case notPickedUp
    case agentHasIt
    case deliveredToWebhook

    @MainActor
    init(_ recording: Recording) {
        self.init(recording, hasAgents: RelayService.shared.hasConnectedAgents)
    }

    /// `hasAgents` stands in for the relay's answer until the phone has
    /// asked it about this note.
    init(_ recording: Recording, hasAgents: Bool) {
        if let hold = recording.hold {
            switch hold {
            case .unlock: self = .heldForUnlock
            case .fairUse: self = .heldForFairUse
            case .tooLong: self = .tooLong
            case .couldntSend: self = .couldntSend
            }
            return
        }
        switch recording.status {
        case .recorded:
            self = recording.source == .watch ? .waitingOnWatch : .waitingToSend
        case .transcribing:
            self = .transcribing
        case .failed:
            self = recording.retryRequested ? .waitingToSend : .couldntTranscribe
        case .completed:
            if !recording.hasSpeechTranscript {
                self = .noSpeech
                return
            }
            let delivery = recording.agentDelivery
            let waiting = delivery.map { $0.waiting > 0 } ?? hasAgents
            if recording.webhookStatus == .failed {
                self = .didntSend
            } else if waiting {
                self = .waitingForAgent
            } else if recording.webhookStatus == .pending || recording.webhookStatus == .sending {
                self = .webhookSending
            } else if let delivery, delivery.pickedUp > 0 {
                self = .agentHasIt
            } else if let delivery, delivery.copies > 0 {
                self = .notPickedUp
            } else if recording.webhookStatus == .delivered {
                self = .deliveredToWebhook
            } else {
                self = .noAgent
            }
        }
    }

    /// Full words, for the note screen's pill.
    var label: String {
        switch self {
        case .waitingToSend: return "Waiting to send"
        case .waitingOnWatch: return "Waiting on your watch"
        case .transcribing: return "Transcribing…"
        case .heldForUnlock: return "Unlock to transcribe"
        case .heldForFairUse: return "Usage limit reached"
        case .tooLong: return "Too long to transcribe"
        case .couldntSend: return "Couldn't send"
        case .couldntTranscribe: return "Couldn't transcribe"
        case .noSpeech: return "No speech detected"
        case .noAgent: return "Saved, no agent connected"
        case .webhookSending: return "Sending to your webhook…"
        case .didntSend: return "Didn't send"
        case .waitingForAgent: return "Waiting for your agent"
        case .notPickedUp: return "Not picked up"
        case .agentHasIt: return "Your agent has it"
        case .deliveredToWebhook: return "Delivered to webhook"
        }
    }

    /// The list row's caption, or nil when the icon says enough.
    var caption: String? {
        switch self {
        case .webhookSending, .waitingForAgent, .agentHasIt, .deliveredToWebhook: return nil
        default: return label
        }
    }

    /// A spinner instead of an icon.
    var isInProgress: Bool {
        self == .transcribing || self == .webhookSending
    }

    /// Not accepted by the server yet, and nothing stops it being sent.
    var isNotYetAccepted: Bool {
        self == .waitingToSend || self == .waitingOnWatch
    }

    var isDone: Bool {
        self == .agentHasIt || self == .deliveredToWebhook
    }

    /// The dot and icon color.
    var tint: Color {
        switch self {
        case .waitingToSend, .waitingOnWatch, .transcribing, .webhookSending: return .secondary
        case .heldForUnlock, .heldForFairUse, .waitingForAgent: return .brandAmber
        case .tooLong, .couldntSend, .couldntTranscribe, .didntSend: return .red
        case .noSpeech, .noAgent, .notPickedUp: return Color(.tertiaryLabel)
        case .agentHasIt, .deliveredToWebhook: return .green
        }
    }

    /// Row icon. Nil while in progress, where the row shows a spinner.
    var systemImage: String? {
        switch self {
        case .transcribing, .webhookSending: return nil
        case .waitingToSend, .waitingOnWatch, .noAgent, .waitingForAgent, .notPickedUp: return "tray"
        case .heldForUnlock: return "lock.fill"
        case .heldForFairUse: return "pause.circle.fill"
        case .tooLong, .couldntSend, .couldntTranscribe, .didntSend: return "exclamationmark.triangle.fill"
        case .noSpeech: return "waveform.slash"
        case .agentHasIt, .deliveredToWebhook: return "checkmark.circle.fill"
        }
    }

    /// Row icon color. Done and quiet notes stay grey so the list isn't a
    /// wall of color.
    var iconTint: Color {
        switch self {
        case .waitingToSend, .waitingOnWatch: return .secondary
        case .agentHasIt, .deliveredToWebhook: return Color(.tertiaryLabel)
        default: return tint
        }
    }
}

/// The small dot-and-words capsule used on Home and on the note screen.
struct StatusPill: View {
    let text: String
    let dot: Color
    var action: String? = nil
    var actionColor: Color = .brandAmber

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
                    .foregroundStyle(actionColor)
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
