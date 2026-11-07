//
//  SubscriberNoticeView.swift
//  Ramble
//
//  One-time notices for early customers (specs/purchase.md "Early buyers"):
//  an active subscriber is told how to stop billing, and a paid-download
//  buyer is told no unlock is needed. Attach `.purchaseNotices()` once, near
//  the root view, to present them.
//

import SwiftUI

struct SubscriberNoticeView: View {
    enum Kind {
        case subscriber
        case earlyBuyer
    }

    var kind: Kind = .subscriber

    @ObservedObject private var purchases = PurchaseService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                OnboardingHeadline(size: 28) {
                    Text(title)
                }
                OnboardingBody(text: message)
            }
            .padding(.top, 32)

            Spacer(minLength: 0)

            switch kind {
            case .subscriber:
                VStack(spacing: 4) {
                    OnboardingPrimaryButton(title: "Manage subscription") {
                        Task {
                            await purchases.manageSubscription()
                            purchases.dismissSubscriberNotice()
                            dismiss()
                        }
                    }
                    OnboardingSecondaryLink(title: "Not now") {
                        purchases.dismissSubscriberNotice()
                        dismiss()
                    }
                }
            case .earlyBuyer:
                OnboardingPrimaryButton(title: "Done") {
                    purchases.dismissEarlyBuyerNotice()
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .presentationDetents([.medium])
        .onDisappear {
            // Shown once: swiping it away counts as "Not now".
            switch kind {
            case .subscriber: purchases.dismissSubscriberNotice()
            case .earlyBuyer: purchases.dismissEarlyBuyerNotice()
            }
        }
    }

    private var title: String {
        switch kind {
        case .subscriber: return PurchaseCopy.subscriberTitle
        case .earlyBuyer: return PurchaseCopy.earlyBuyerTitle
        }
    }

    private var message: String {
        switch kind {
        case .subscriber: return PurchaseCopy.subscriberBody
        case .earlyBuyer: return PurchaseCopy.earlyBuyerBody
        }
    }
}

// MARK: - Presentation

extension View {
    /// Presents the early-buyer and subscriber notices when PurchaseService
    /// says they're due. The early-buyer notice goes first.
    func purchaseNotices() -> some View {
        modifier(PurchaseNoticesModifier())
    }
}

private struct PurchaseNoticesModifier: ViewModifier {
    @ObservedObject private var purchases = PurchaseService.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            SubscriberNoticeView(kind: purchases.showEarlyBuyerNotice ? .earlyBuyer : .subscriber)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { purchases.showEarlyBuyerNotice || purchases.showSubscriberNotice },
            set: { presented in
                guard !presented else { return }
                if purchases.showEarlyBuyerNotice {
                    purchases.dismissEarlyBuyerNotice()
                } else {
                    purchases.dismissSubscriberNotice()
                }
            }
        )
    }
}

#Preview {
    SubscriberNoticeView(kind: .subscriber)
}
