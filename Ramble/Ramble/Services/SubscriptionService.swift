//
//  SubscriptionService.swift
//  Ramble
//

import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    static let premiumProductId = "dev.goodloop.ramble.premium.monthly2"

    @Published private(set) var isPremium = false
    @Published private(set) var product: Product?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var currentJWSTransaction: String?

    private var transactionListener: Task<Void, Never>?

    static let devOverrideUserDefaultsKey = "devOverrideKey"

    /// Developer override key — bypasses subscription check on both client and proxy.
    /// Stored in UserDefaults, entered via hidden Settings easter egg.
    nonisolated var devOverrideKey: String? {
        let key = UserDefaults.standard.string(forKey: Self.devOverrideUserDefaultsKey)
        return (key != nil && !key!.isEmpty) ? key : nil
    }

    func setDevOverrideKey(_ key: String?) {
        UserDefaults.standard.set(key, forKey: Self.devOverrideUserDefaultsKey)
        Task { await refreshStatus() }
    }

    private init() {
        transactionListener = listenForTransactionUpdates()
        Task { await refreshStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    func start() async {
        await fetchProduct()
        await refreshStatus()
    }

    func fetchProduct() async {
        do {
            let products = try await Product.products(for: [Self.premiumProductId])
            product = products.first
        } catch {
            print("Failed to fetch products: \(error.localizedDescription)")
        }
    }

    func purchase() async throws -> Bool {
        guard let product else { return false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshStatus()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshStatus()
    }

    // MARK: - Status

    func refreshStatus() async {
        var foundPremium = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if transaction.productID == Self.premiumProductId {
                foundPremium = true
                expirationDate = transaction.expirationDate
                currentJWSTransaction = result.jwsRepresentation
            }
        }

        // Dev override key grants premium access without a subscription
        isPremium = foundPremium || devOverrideKey != nil
        if !foundPremium {
            expirationDate = nil
            currentJWSTransaction = nil
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshStatus()
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let value):
            return value
        }
    }
}

enum SubscriptionError: Error, LocalizedError {
    case verificationFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Transaction verification failed"
        case .purchaseFailed:
            return "Purchase could not be completed"
        }
    }
}
