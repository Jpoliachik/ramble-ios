//
//  UnlockSheet.swift
//  Ramble
//
//  The one-time unlock (specs/purchase.md "Unlock sheet", "Purchase outcomes").
//  Price comes only from the App Store.
//

import StoreKit
import SwiftUI

struct UnlockSheet: View {
    @ObservedObject private var purchases = PurchaseService.shared
    @ObservedObject private var accounts = AccountService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if isUnlocked {
                        unlockedSection
                    } else {
                        purchaseSection
                        restoreSection
                    }
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            purchases.clearMessage()
            await purchases.loadProduct()
        }
        .onChange(of: purchases.state) { _, newState in
            guard newState == .succeeded else { return }
            HapticService.success()
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            }
        }
    }

    private var isUnlocked: Bool {
        purchases.state == .succeeded || accounts.account?.unlocked == true
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 16) {
            RambleBarsMark(size: 56)
                .accessibilityHidden(true)

            OnboardingHeadline(size: 34) {
                Text("Unlock ") + Text("Ramble").italic()
            }

            OnboardingBody(text: "Keep sending every note from your watch and iPhone.")
        }
    }

    private var unlockedSection: some View {
        Label(PurchaseCopy.unlocked, systemImage: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.obInk)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .accessibilityElement(children: .combine)
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            OnboardingPrimaryButton(
                title: buttonTitle,
                isDisabled: purchases.product == nil || purchases.state.isBusy
                    || purchases.state == .pending || purchases.state == .finishing,
                isLoading: purchases.state == .purchasing
            ) {
                Task { await purchases.purchase() }
            }

            if purchases.product == nil && purchases.productUnavailable {
                statusText(PurchaseCopy.storeUnreachable, isError: false)
            }

            Text(PurchaseCopy.oneTime)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.obInkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            if let message = purchases.state.message {
                statusText(message, isError: purchases.state.isError)
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: purchases.state)
    }

    private var restoreSection: some View {
        Button {
            HapticService.buttonTap()
            Task { await purchases.restore() }
        } label: {
            Group {
                if purchases.state == .restoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.obInkSoft)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(purchases.state.isBusy)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Link("Terms of Use", destination: PurchaseService.termsURL)
            Link("Privacy Policy", destination: PurchaseService.privacyURL)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.obInkFaint)
    }

    // MARK: - Helpers

    private var buttonTitle: String {
        if let price = purchases.product?.displayPrice {
            return "Unlock for \(price)"
        }
        return "Unlock"
    }

    private func statusText(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(isError ? Color.red : Color.obInkSoft)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    UnlockSheet()
}
