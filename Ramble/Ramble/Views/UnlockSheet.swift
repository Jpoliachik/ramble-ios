//
//  UnlockSheet.swift
//  Ramble
//
//  The one-time unlock (specs/purchase.md "Unlock sheet", "Purchase outcomes").
//  A short note from the developer, the price from the App Store, and the
//  outcome of each purchase or restore next to the control that caused it.
//

import StoreKit
import SwiftUI

struct UnlockSheet: View {
    @ObservedObject private var purchases = PurchaseService.shared
    @ObservedObject private var accounts = AccountService.shared
    @Environment(\.dismiss) private var dismiss

    /// Which control the person last tapped, so its result shows beside it.
    @State private var lastAction: Action?

    private enum Action { case purchase, restore }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    DeveloperNote(isUnlocked: isUnlocked)
                    if isUnlocked {
                        unlockedSection
                    } else {
                        purchaseSection
                        restoreSection
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
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
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            }
        }
    }

    private var isUnlocked: Bool {
        purchases.state == .succeeded || accounts.account?.unlocked == true
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            RambleBarsMark(size: 44)
                .accessibilityHidden(true)

            OnboardingHeadline(size: 34) {
                Text("Unlock ") + Text("Ramble").italic().foregroundColor(.brandAmber)
            }

            if !isUnlocked {
                VStack(spacing: 2) {
                    Text(PurchaseCopy.unlockTagline)
                        .foregroundStyle(Color.obInk)
                    Text(PurchaseCopy.unlockTaglineSecond)
                        .foregroundStyle(Color.obInkSoft)
                }
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Unlocked

    private var unlockedSection: some View {
        VStack(spacing: 6) {
            Label(PurchaseCopy.unlocked, systemImage: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.obInk)
                .symbolRenderingMode(.multicolor)
            Text("Everything you say goes where you send it.")
                .font(.system(size: 14))
                .foregroundStyle(Color.obInkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Purchase

    @ViewBuilder
    private var purchaseSection: some View {
        VStack(spacing: 10) {
            switch purchases.state {
            case .pending:
                waitingBlock(icon: "hourglass", text: PurchaseCopy.pending)
            case .finishing:
                waitingBlock(icon: "checkmark.circle", text: PurchaseCopy.finishing)
            default:
                OnboardingPrimaryButton(
                    title: buttonTitle,
                    isDisabled: purchases.product == nil || purchases.state.isBusy,
                    isLoading: purchases.state == .purchasing
                ) {
                    lastAction = .purchase
                    Task { await purchases.purchase() }
                }

                if purchases.product == nil && purchases.productUnavailable {
                    HStack(spacing: 6) {
                        statusText(PurchaseCopy.storeUnreachable, isError: false)
                        Button("Try again") {
                            Task { await purchases.loadProduct() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .tint(.brandAmber)
                    }
                } else {
                    Text(PurchaseCopy.oneTime)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.obInkSoft)
                }

                if lastAction != .restore, let message = purchases.state.message {
                    statusText(message, isError: purchases.state.isError)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: purchases.state)
    }

    /// Pending and finishing replace the button: nothing to tap, nothing lost.
    private func waitingBlock(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.brandAmber)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.obInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.brandAmberSoft))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Restore

    private var restoreSection: some View {
        VStack(spacing: 4) {
            Button {
                HapticService.buttonTap()
                lastAction = .restore
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
            .disabled(purchases.state.isBusy || purchases.state == .pending || purchases.state == .finishing)

            if lastAction == .restore, let message = purchases.state.message,
               purchases.state != .pending, purchases.state != .finishing {
                statusText(message, isError: purchases.state.isError)
            }
        }
    }

    // MARK: - Footer

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

// MARK: - A note from the developer

/// A short, signed note from the person who makes Ramble
/// (specs/purchase.md "Unlock sheet"). Words in PurchaseCopy.developerNote.
private struct DeveloperNote: View {
    let isUnlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            (Text(PurchaseCopy.developerNoteGreeting) + Text(PurchaseCopy.developerNoteSignature).italic() + Text("!"))
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(Color.obInk)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.obInkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(PurchaseCopy.developerNoteSignature)
                .font(.system(size: 24, design: .serif).italic())
                .foregroundStyle(Color.obInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SunsetWash().clipShape(RoundedRectangle(cornerRadius: 16)))
        .accessibilityElement(children: .combine)
    }

    private var paragraphs: [String] {
        isUnlocked ? PurchaseCopy.developerNoteThanks : PurchaseCopy.developerNote
    }
}

/// The website hero's light sunset wash (website/src/app/globals.css
/// `.sunset-wash`): ember, coral, rose and plum glows rising from the bottom
/// over a warm cream. In dark mode the same glows sit over a dark warm base.
private struct SunsetWash: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Glow {
        let x: CGFloat
        let color: Color
        let opacity: Double
    }

    private let glows = [
        Glow(x: 0.12, color: Color(red: 244 / 255, green: 150 / 255, blue: 70 / 255), opacity: 0.22),
        Glow(x: 0.40, color: Color(red: 238 / 255, green: 118 / 255, blue: 72 / 255), opacity: 0.18),
        Glow(x: 0.68, color: Color(red: 220 / 255, green: 98 / 255, blue: 96 / 255), opacity: 0.16),
        Glow(x: 0.92, color: Color(red: 150 / 255, green: 82 / 255, blue: 140 / 255), opacity: 0.14),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: baseColors, startPoint: .top, endPoint: .bottom)
                ForEach(glows.indices, id: \.self) { i in
                    let glow = glows[i]
                    let boost = colorScheme == .dark ? 1.4 : 1.0
                    // CSS radial-gradient(38% 60% at x 100%, color, transparent 70%),
                    // drawn as a blurred ellipse so it has no hard edges.
                    Ellipse()
                        .fill(glow.color.opacity(glow.opacity * boost * 0.45))
                        .frame(width: w * 0.6, height: h * 1.1)
                        .position(x: w * glow.x, y: h)
                        .blur(radius: 48)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var baseColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.13, green: 0.11, blue: 0.10),
                Color(red: 0.15, green: 0.12, blue: 0.11),
                Color(red: 0.19, green: 0.13, blue: 0.12),
            ]
        }
        return [
            Color(red: 247 / 255, green: 239 / 255, blue: 229 / 255),
            Color(red: 246 / 255, green: 236 / 255, blue: 225 / 255),
            Color(red: 244 / 255, green: 230 / 255, blue: 219 / 255),
        ]
    }
}

#Preview {
    UnlockSheet()
}
