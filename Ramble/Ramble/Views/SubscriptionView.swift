//
//  SubscriptionView.swift
//  Ramble
//

import StoreKit
import SwiftUI

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
                .padding(.vertical, 16)
            }
            .navigationTitle("Ramble Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            if subscriptionService.isPremium {
                Label("Premium Active", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                if let expiration = subscriptionService.expirationDate {
                    Text("Renews \(expiration.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Unlock Cloud Transcription")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(
                icon: "bolt.fill",
                color: .orange,
                title: "Cloud-Powered Models",
                subtitle: "Higher accuracy transcription via Groq Whisper"
            )
            FeatureRow(
                icon: "slider.horizontal.3",
                color: .blue,
                title: "Choose Your Model",
                subtitle: "Pick the speed/accuracy balance that works for you"
            )
            FeatureRow(
                icon: "lock.shield",
                color: .green,
                title: "Still Private",
                subtitle: "Audio processed and discarded. Nothing stored on servers."
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var pricingSection: some View {
        VStack(spacing: 6) {
            if let product = subscriptionService.product {
                Text(product.displayPrice)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("per month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("$2.99")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("per month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var buttonsSection: some View {
        if subscriptionService.isPremium {
            Button("Manage Subscription") {
                openSubscriptionManagement()
            }
            .buttonStyle(.bordered)
        } else {
            VStack(spacing: 12) {
                Button {
                    purchasePremium()
                } label: {
                    if isPurchasing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    } else {
                        Text("Subscribe")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing || subscriptionService.product == nil)

                Button("Restore Purchases") {
                    Task { await subscriptionService.restore() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Payment is charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://github.com/Jpoliachik/ramble-ios")!)
            }
            .font(.caption2)
        }
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
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SubscriptionView()
}
