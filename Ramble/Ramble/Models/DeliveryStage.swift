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
    case tooLong
    case couldntSend
    case couldntTranscribe
    case noSpeech
    /// No eligible agent and no webhook.
    case noAgent
    case webhookSending
    case didntSend
    case waitingForAgent
    /// An agent is connected but the phone hasn't heard from the relay
    /// about this note yet, so it claims neither waiting nor picked up.
    case checkingDelivery
    /// Every agent copy was removed unread.
    case notPickedUp
    case agentHasIt
    case deliveredToWebhook

    @MainActor
    init(_ recording: Recording) {
        self.init(recording, hasAgents: RelayService.shared.hasConnectedAgents)
    }

    /// Until the relay has answered about this note, `hasAgents` decides
    /// between "Checking delivery…" and "Saved, no agent connected"; the
    /// phone never guesses "Waiting for your agent".
    init(_ recording: Recording, hasAgents: Bool) {
        if let hold = recording.hold {
            switch hold {
            case .unlock: self = .heldForUnlock
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
            if recording.webhookStatus == .failed {
                self = .didntSend
            } else if let delivery, delivery.waiting > 0 {
                self = .waitingForAgent
            } else if delivery == nil && hasAgents {
                self = .checkingDelivery
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
        case .heldForUnlock: return "Unlock to send"
        case .tooLong: return "Too long to transcribe"
        case .couldntSend: return "Couldn't send"
        case .couldntTranscribe: return "Couldn't transcribe"
        case .noSpeech: return "No speech detected"
        case .noAgent: return "Saved, no agent connected"
        case .webhookSending: return "Sending to your webhook…"
        case .didntSend: return "Didn't send"
        case .waitingForAgent: return "Waiting for your agent"
        case .checkingDelivery: return "Checking delivery…"
        case .notPickedUp: return "Not picked up"
        case .agentHasIt: return "Your agent has it"
        case .deliveredToWebhook: return "Delivered to webhook"
        }
    }

    /// `label`, counting agents when the note went to more than one
    /// ("2 of 3 agents have it", "Waiting for your agents").
    func label(for recording: Recording) -> String {
        guard let delivery = recording.agentDelivery else { return label }
        switch self {
        case .agentHasIt: return delivery.hasItLabel
        case .waitingForAgent: return delivery.waitingLabel
        default: return label
        }
    }

    /// The list row's caption, or nil when the icon says enough.
    var caption: String? {
        switch self {
        case .webhookSending, .waitingForAgent, .checkingDelivery, .agentHasIt, .deliveredToWebhook: return nil
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

    /// The dot and icon color. Green is done, amber needs the person, red
    /// failed; everything on its way stays grey.
    var tint: Color {
        switch self {
        case .waitingToSend, .waitingOnWatch, .transcribing, .webhookSending, .checkingDelivery, .waitingForAgent: return .secondary
        case .heldForUnlock, .notPickedUp: return .brandAmber
        case .tooLong, .couldntSend, .couldntTranscribe, .didntSend: return .red
        case .noSpeech, .noAgent: return Color(.tertiaryLabel)
        case .agentHasIt, .deliveredToWebhook: return .green
        }
    }

    /// This note's dot color: a note waiting on its agent turns amber once
    /// it has waited over 12 hours, the same rule as Home's pill.
    func tint(for recording: Recording, now: Date = Date()) -> Color {
        if self == .waitingForAgent && now.timeIntervalSince(recording.waitingSince) > HomeStatus.longWait {
            return .brandAmber
        }
        return tint
    }

    /// Row icon. Nil while in progress, where the row shows a spinner.
    var systemImage: String? {
        switch self {
        case .transcribing, .webhookSending: return nil
        case .waitingToSend, .waitingOnWatch: return "clock"
        case .noAgent, .waitingForAgent, .checkingDelivery, .notPickedUp: return "tray"
        case .heldForUnlock: return "lock.fill"
        case .tooLong, .couldntSend, .couldntTranscribe, .didntSend: return "exclamationmark.triangle.fill"
        case .noSpeech: return "waveform.slash"
        case .agentHasIt, .deliveredToWebhook: return "checkmark.circle.fill"
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
