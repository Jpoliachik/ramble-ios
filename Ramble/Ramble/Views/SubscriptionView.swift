//
//  SubscriptionView.swift
//  Ramble
//

import StoreKit
import SwiftUI

private enum SubscriptionLinks {
    static let appleEULA = URL(string: "https://apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://goodloop.dev/ramble/privacy")!
    static let manage = URL(string: "https://apps.apple.com/account/subscriptions")!
}

struct SubscriptionView: View {
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    featuresSection
                    pricingSection
                    buttonsSection
                    footerSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandRed)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 16) {
            OnboardingIllustration(name: "illustration-upgrade")

            if subscriptionService.isPremium {
                OnboardingHeadline(size: 28) {
                    Text("Premium ") + Text("active.").italic()
                }

                if let expiration = subscriptionService.expirationDate {
                    Text("Renews \(expiration.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }
            } else {
                OnboardingHeadline(size: 28) {
                    Text("Best-in-class ") + Text("transcription models.").italic()
                }
            }
        }
    }

    private var featuresSection: some View {
        BrandCard {
            BrandFeatureRow(
                icon: "bolt.fill",
                title: "Top-tier accuracy",
                subtitle: "The best models available. Updated as new ones are released."
            )
            BrandRowDivider()
            BrandFeatureRow(
                icon: "slider.horizontal.3",
                title: "Pick the model that fits",
                subtitle: "Speed, accents, multilingual — your call"
            )
            BrandRowDivider()
            BrandFeatureRow(
                icon: "lock.shield",
                title: "Still private",
                subtitle: "Audio routes through our open-source proxy. Nothing stored."
            )
        }
    }

    private var pricingSection: some View {
        VStack(spacing: 2) {
            Text(displayPrice)
                .font(.system(size: 44, design: .serif).weight(.medium))
                .tracking(-0.8)
                .foregroundStyle(Color.obInk)

            Text("per month")
                .font(.system(size: 14))
                .foregroundStyle(Color.obInkSoft)
        }
    }

    @ViewBuilder
    private var buttonsSection: some View {
        if subscriptionService.isPremium {
            OnboardingSurfaceButton(title: "Manage subscription") {
                openSubscriptionManagement()
            }
        } else {
            VStack(spacing: 14) {
                OnboardingPrimaryButton(
                    title: "Subscribe",
                    isDisabled: subscriptionService.product == nil,
                    isLoading: isPurchasing
                ) {
                    purchasePremium()
                }

                Button("Restore purchases") {
                    Task { await subscriptionService.restore() }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.brandRed)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 10) {
            Text("Payment is charged to your Apple ID. Renews monthly unless cancelled at least 24 hours before the period ends.")
                .font(.system(size: 11))
                .foregroundStyle(Color.obInkFaint)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: SubscriptionLinks.appleEULA)
                Link("Privacy Policy", destination: SubscriptionLinks.privacy)
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.brandRed)
        }
    }

    // MARK: - Helpers

    private var displayPrice: String {
        subscriptionService.product?.displayPrice ?? "$3.99"
    }

    // MARK: - Actions

    private func purchasePremium() {
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                let success = try await subscriptionService.purchase()
                if success { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }

    private func openSubscriptionManagement() {
        UIApplication.shared.open(SubscriptionLinks.manage)
    }
}

// MARK: - Brand feature row

/// Mirrors `TranscriptionModelRow`'s visual proportions so the subscription
/// feature list reads as the same kind of branded surface card.
private struct BrandFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.obInk)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.obInk)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.obInkFaint)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

#Preview {
    SubscriptionView()
}
