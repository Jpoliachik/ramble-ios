//
//  PurchaseService.swift
//  Ramble
//
//  The one-time unlock (specs/purchase.md). The relay decides who is unlocked;
//  this service gets Apple's signed records to it: the unlock purchase, an
//  early buyer's app purchase record, or an active subscriber's transaction.
//  Unlock transactions are finished only after the relay accepted them (or
//  rejected them for good), so a purchase the relay never heard about is
//  delivered again on the next launch.
//

import Combine
import Foundation
import StoreKit
import UIKit

enum PurchaseState: Equatable {
    case idle
    case purchasing
    case restoring
    /// Ask to Buy or a pending payment. Held notes stay held.
    case pending
    /// Paid, but the relay hasn't confirmed it yet. Retrying.
    case finishing
    case failed(String)
    /// A neutral result, e.g. "No purchase found for this Apple ID."
    case notice(String)
    case succeeded

    /// Line to show under the unlock button or the Restore row, if any.
    var message: String? {
        switch self {
        case .pending: return PurchaseCopy.pending
        case .finishing: return PurchaseCopy.finishing
        case .failed(let text), .notice(let text): return text
        case .idle, .purchasing, .restoring, .succeeded: return nil
        }
    }

    var isError: Bool {
        if case .failed = self { return true }
        return false
    }

    var isBusy: Bool {
        self == .purchasing || self == .restoring
    }
}

/// On-screen strings from specs/purchase.md.
enum PurchaseCopy {
    static let unlocked = "Unlocked"
    static let oneTime = "One-time purchase. No subscription."
    static let fairUse = "Includes up to 100 hours of audio each month."
    static let storeUnreachable = "Can't reach the App Store. Try again in a moment."
    static let failed = "Purchase didn't go through. Try again."
    static let pending = "Waiting for approval. Your notes are kept and will transcribe once it's approved."
    static let finishing = "Purchase complete. Finishing setup. Your notes will transcribe shortly."
    static let nothingToRestore = "No purchase found for this Apple ID."
    static let tooManyInboxes = "This purchase is in use on 5 iPhones. Each fresh start after a reinstall counts as one. A spot opens when one of them goes 90 days without sending a note."
    // Not worded in the spec: a first purchase made for another inbox.
    static let wrongAccount = "This purchase belongs to another Ramble setup. Contact support@ramble.watch for help."
    static let earlyBuyerTitle = "You're all set."
    static let earlyBuyerBody = "You bought Ramble early, so every note transcribes. No unlock needed."
    static let subscriberTitle = "Cloud transcription is now included for everyone."
    static let subscriberBody = "You don't need your subscription anymore. Apple keeps billing it until you cancel."
    static let subscriberSettingsRow = "Your old subscription is still active"
}

@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    static let unlockProductId = "dev.goodloop.ramble.unlock"
    /// The old monthly cloud subscription. Accepted by the relay only as
    /// early-subscriber proof; no longer sold.
    static let legacySubscriptionProductId = "dev.goodloop.ramble.premium.monthly2"

    static let termsURL = URL(string: "https://ramble.watch/terms")!
    static let privacyURL = URL(string: "https://ramble.watch/privacy")!
    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    @Published private(set) var product: Product?
    /// True once loading the product failed or the store returned nothing.
    @Published private(set) var productUnavailable = false
    @Published private(set) var state: PurchaseState = .idle

    /// True while an early subscriber should see the "stop billing" notice.
    @Published private(set) var showSubscriberNotice = false
    /// True while the old subscription is still set to renew (Settings row).
    @Published private(set) var subscriptionStillRenews = false
    /// One-time "You bought Ramble early" notice.
    @Published private(set) var showEarlyBuyerNotice = false

    private enum Keys {
        static let checkedAccountTokens = "purchase.checkedAccountTokens"
        static let retryProofs = "purchase.retryProofs"
        static let earlyBuyerProofSent = "purchase.earlyBuyerProofSent"
        static let earlyBuyerNoticeShown = "purchase.earlyBuyerNoticeShown"
        static let subscriberNoticeDismissed = "purchase.subscriberNoticeDismissed"
    }

    private enum SubmitOutcome {
        case accepted(RelayAccount)
        case rejected(String)
        case retryLater
    }

    private enum ProofOutcome {
        case unlocked
        case rejected(String)
        case nothingFound
        case retryLater
    }

    /// 403 reasons that won't change by sending the same record again.
    private static let finalReasons: Set<String> = ["invalid_transaction", "wrong_account", "too_many_inboxes"]

    private let defaults = UserDefaults.standard
    private var started = false
    private var isChecking = false
    private var updatesTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Launch

    /// Load the product, listen for Transaction.updates, confirm unfinished or
    /// new transactions with the relay, and run the early-buyer check.
    func start() async {
        guard !started else { return }
        started = true

        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handleUpdate(result)
            }
        }

        // Fires now with the current account, then on every change (the inbox
        // appears, a refresh, an unlock).
        AccountService.shared.$account
            .sink { [weak self] account in
                guard let account else { return }
                Task { await self?.accountDidChange(account) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { await self?.appWillEnterForeground() }
            }
            .store(in: &cancellables)

        await loadProduct()
        await refreshSubscriptionStatus()
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            let products = try await Product.products(for: [Self.unlockProductId])
            product = products.first
            productUnavailable = product == nil
        } catch {
            productUnavailable = true
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard !state.isBusy else { return }
        if product == nil { await loadProduct() }
        guard let product else {
            state = .failed(PurchaseCopy.storeUnreachable)
            return
        }

        state = .purchasing

        if AccountService.shared.account?.accountToken == nil {
            await AccountService.shared.refresh()
        }
        guard let token = AccountService.shared.account?.accountToken,
              let accountToken = UUID(uuidString: token) else {
            state = .failed(PurchaseCopy.failed)
            return
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase(options: [.appAccountToken(accountToken)])
        } catch {
            state = Self.isUserCancelled(error) ? .idle : .failed(PurchaseCopy.failed)
            return
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                state = .failed(PurchaseCopy.failed)
                return
            }
            switch await confirm(transaction, jws: verification.jwsRepresentation) {
            case .accepted:
                state = .succeeded
            case .rejected(let reason):
                state = .failed(Self.copy(forReason: reason, restoring: false))
            case .retryLater:
                state = .finishing
                scheduleRetry()
            }
        case .userCancelled:
            state = .idle
        case .pending:
            state = .pending
        @unknown default:
            state = .idle
        }
    }

    // MARK: - Restore

    func restore() async {
        guard !state.isBusy else { return }
        state = .restoring

        var storeUnreachable = false
        do {
            try await AppStore.sync()
        } catch {
            if Self.isUserCancelled(error) {
                state = .idle
                return
            }
            // Keep going with what's on the device.
            storeUnreachable = true
        }

        if AccountService.shared.account == nil {
            await AccountService.shared.refresh()
        }

        let unfinishedClear = await confirmUnfinished()

        if AccountService.shared.account?.unlocked == true {
            state = .succeeded
            await refreshSubscriptionStatus()
            return
        }

        switch await submitProofs() {
        case .unlocked:
            markProofsChecked()
            state = .succeeded
        case .rejected(let reason):
            markProofsChecked()
            state = .failed(Self.copy(forReason: reason, restoring: true))
        case .nothingFound:
            markProofsChecked()
            if !unfinishedClear {
                state = .finishing
                scheduleRetry()
            } else if storeUnreachable {
                state = .failed(PurchaseCopy.storeUnreachable)
            } else {
                state = .notice(PurchaseCopy.nothingToRestore)
            }
        case .retryLater:
            defaults.set(true, forKey: Keys.retryProofs)
            state = .finishing
            scheduleRetry()
        }

        await refreshSubscriptionStatus()
    }

    /// Clears a finished result (error, "No purchase found", "Unlocked") so a
    /// reopened sheet starts clean. In-flight states are kept.
    func clearMessage() {
        switch state {
        case .failed, .notice, .succeeded: state = .idle
        default: break
        }
    }

    // MARK: - Inbox creation

    /// Proof to include in POST /inboxes when the phone creates an inbox (buyer
    /// on a new iPhone). Returns ["signed_transaction": jws] or
    /// ["app_transaction": jws] or nil.
    func inboxCreationProof() async -> [String: String]? {
        if let jws = await currentUnlockJWS(skipXcode: true) {
            return ["signed_transaction": jws]
        }
        if let subscription = await activeSubscription(), !subscription.isXcode {
            return ["signed_transaction": subscription.jws]
        }
        if let jws = await appTransactionJWS() {
            defaults.set(true, forKey: Keys.earlyBuyerProofSent)
            return ["app_transaction": jws]
        }
        return nil
    }

    // MARK: - Subscriber notice

    func dismissSubscriberNotice() {
        defaults.set(true, forKey: Keys.subscriberNoticeDismissed)
        showSubscriberNotice = false
    }

    func dismissEarlyBuyerNotice() {
        defaults.set(true, forKey: Keys.earlyBuyerNoticeShown)
        showEarlyBuyerNotice = false
    }

    /// Opens Apple's subscription settings, then re-reads whether the old
    /// subscription still renews.
    func manageSubscription() async {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let scene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                UIApplication.shared.open(Self.manageSubscriptionsURL, options: [:], completionHandler: nil)
            }
        } else {
            UIApplication.shared.open(Self.manageSubscriptionsURL, options: [:], completionHandler: nil)
        }
        await refreshSubscriptionStatus()
    }

    // MARK: - Events

    private func accountDidChange(_ account: RelayAccount) async {
        if defaults.bool(forKey: Keys.earlyBuyerProofSent) {
            // First account after creating the inbox with an app purchase record.
            defaults.set(false, forKey: Keys.earlyBuyerProofSent)
            if account.unlocked { presentEarlyBuyerNotice() }
        }
        updateSubscriberNotice(unlocked: account.unlocked)
        await runBackgroundCheck()
    }

    private func appWillEnterForeground() async {
        await refreshSubscriptionStatus()
        await runBackgroundCheck()
    }

    private func handleUpdate(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }

        guard transaction.productID == Self.unlockProductId else {
            // Old subscription renewals: nothing to send now; currentEntitlements
            // carries the proof when it's needed.
            await transaction.finish()
            await refreshSubscriptionStatus()
            return
        }

        if transaction.revocationDate != nil {
            // Refunded. The relay hears it from Apple; just re-read the account.
            await transaction.finish()
            await AccountService.shared.refresh()
            return
        }

        // Ask to Buy approved, a purchase on another device, or a redelivery.
        switch await confirm(transaction, jws: result.jwsRepresentation) {
        case .accepted:
            if Self.isWaiting(state) { state = .succeeded }
        case .rejected(let reason):
            if Self.isWaiting(state) { state = .failed(Self.copy(forReason: reason, restoring: false)) }
        case .retryLater:
            if state == .pending { state = .finishing }
            scheduleRetry()
        }
    }

    // MARK: - Confirming with the relay

    private func runBackgroundCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        if !(await confirmPendingWork()) {
            scheduleRetry()
        }
    }

    /// Unfinished unlock transactions, then (once per inbox, or until a retry
    /// succeeds) the Apple ID's proofs. Returns true when nothing is left to retry.
    private func confirmPendingWork() async -> Bool {
        var clear = await confirmUnfinished()

        guard let account = AccountService.shared.account,
              !account.unlocked,
              let token = account.accountToken else {
            if AccountService.shared.account?.unlocked == true {
                defaults.set(false, forKey: Keys.retryProofs)
            }
            return clear
        }

        let checked = defaults.stringArray(forKey: Keys.checkedAccountTokens) ?? []
        let due = defaults.bool(forKey: Keys.retryProofs) || !checked.contains(token)
        guard due else { return clear }

        switch await submitProofs() {
        case .unlocked:
            markProofsChecked()
            if Self.isWaiting(state) { state = .succeeded }
        case .rejected(let reason):
            markProofsChecked()
            if state == .finishing { state = .failed(Self.copy(forReason: reason, restoring: true)) }
        case .nothingFound:
            markProofsChecked()
        case .retryLater:
            defaults.set(true, forKey: Keys.retryProofs)
            clear = false
        }
        return clear
    }

    /// Sends every unfinished unlock transaction. Returns false if any must be retried.
    private func confirmUnfinished() async -> Bool {
        var clear = true
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.unlockProductId else {
                await transaction.finish()
                continue
            }
            if transaction.revocationDate != nil {
                await transaction.finish()
                continue
            }
            switch await confirm(transaction, jws: result.jwsRepresentation) {
            case .accepted:
                if Self.isWaiting(state) { state = .succeeded }
            case .rejected(let reason):
                if Self.isWaiting(state) { state = .failed(Self.copy(forReason: reason, restoring: false)) }
            case .retryLater:
                clear = false
            }
        }
        return clear
    }

    /// Submits one unlock transaction and finishes it once the relay has
    /// accepted it or rejected it for good.
    private func confirm(_ transaction: StoreKit.Transaction, jws: String) async -> SubmitOutcome {
        let outcome = await submit(["signed_transaction": jws])
        switch outcome {
        case .accepted, .rejected:
            await transaction.finish()
        case .retryLater:
            break
        }
        return outcome
    }

    /// Unlock purchase, then active subscription, then app purchase record.
    private func submitProofs() async -> ProofOutcome {
        let wasUnlocked = AccountService.shared.account?.unlocked == true

        var proofs: [(body: [String: String], isAppTransaction: Bool)] = []
        if let jws = await currentUnlockJWS(skipXcode: false) {
            proofs.append((body: ["signed_transaction": jws], isAppTransaction: false))
        }
        if let subscription = await activeSubscription() {
            proofs.append((body: ["signed_transaction": subscription.jws], isAppTransaction: false))
        }
        if let jws = await appTransactionJWS() {
            proofs.append((body: ["app_transaction": jws], isAppTransaction: true))
        }
        guard !proofs.isEmpty else { return .nothingFound }

        var rejection: String?
        var retry = false
        for proof in proofs {
            switch await submit(proof.body) {
            case .accepted(let account):
                if account.unlocked {
                    if proof.isAppTransaction && !wasUnlocked { presentEarlyBuyerNotice() }
                    updateSubscriberNotice(unlocked: true)
                    return .unlocked
                }
            case .rejected(let reason):
                if rejection.map({ Self.rank($0) < Self.rank(reason) }) ?? true {
                    rejection = reason
                }
            case .retryLater:
                retry = true
            }
        }
        if retry { return .retryLater }
        if let rejection { return .rejected(rejection) }
        return .nothingFound
    }

    private func submit(_ body: [String: String]) async -> SubmitOutcome {
        do {
            let account = try await AccountService.shared.submitEntitlement(body)
            AccountService.shared.apply(account)
            return .accepted(account)
        } catch {
            if let reason = Self.finalReason(error) { return .rejected(reason) }
            // Offline, 5xx, "unavailable", rate limited, or no inbox yet.
            return .retryLater
        }
    }

    private func markProofsChecked() {
        defaults.set(false, forKey: Keys.retryProofs)
        guard let token = AccountService.shared.account?.accountToken else { return }
        var checked = defaults.stringArray(forKey: Keys.checkedAccountTokens) ?? []
        if !checked.contains(token) {
            checked.append(token)
            defaults.set(checked, forKey: Keys.checkedAccountTokens)
        }
    }

    /// Keeps trying while the app runs: 15s, 30s, 60s ... up to 5 minutes.
    /// Each launch and each return to the foreground also tries again.
    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            var delay: Double = 15
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                if self.isChecking {
                    delay = min(delay * 2, 300)
                    continue
                }
                self.isChecking = true
                let clear = await self.confirmPendingWork()
                self.isChecking = false
                if clear { break }
                delay = min(delay * 2, 300)
            }
            self?.retryTask = nil
        }
    }

    // MARK: - Records on this Apple ID

    private func currentUnlockJWS(skipXcode: Bool) async -> String? {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.unlockProductId,
                  transaction.revocationDate == nil,
                  transaction.ownershipType == .purchased else { continue }
            if skipXcode && transaction.environment == .xcode { continue }
            return result.jwsRepresentation
        }
        return nil
    }

    /// The old subscription while active or in its grace period.
    private func activeSubscription() async -> (jws: String, willRenew: Bool, isXcode: Bool)? {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.legacySubscriptionProductId,
                  transaction.revocationDate == nil else { continue }

            var willRenew = false
            if let groupID = transaction.subscriptionGroupID,
               let statuses = try? await Product.SubscriptionInfo.status(for: groupID) {
                for status in statuses {
                    guard status.state == .subscribed
                            || status.state == .inGracePeriod
                            || status.state == .inBillingRetryPeriod else { continue }
                    if case .verified(let renewal) = status.renewalInfo, renewal.willAutoRenew {
                        willRenew = true
                    }
                }
            }
            return (result.jwsRepresentation, willRenew, transaction.environment == .xcode)
        }
        return nil
    }

    private func appTransactionJWS() async -> String? {
        guard let result = try? await AppTransaction.shared,
              case .verified(let appTransaction) = result,
              appTransaction.environment != .xcode else { return nil }
        return result.jwsRepresentation
    }

    private func refreshSubscriptionStatus() async {
        subscriptionStillRenews = await activeSubscription()?.willRenew ?? false
        updateSubscriberNotice(unlocked: AccountService.shared.account?.unlocked == true)
    }

    private func updateSubscriberNotice(unlocked: Bool) {
        let renews = subscriptionStillRenews && unlocked
        showSubscriberNotice = renews && !defaults.bool(forKey: Keys.subscriberNoticeDismissed)
    }

    private func presentEarlyBuyerNotice() {
        guard !defaults.bool(forKey: Keys.earlyBuyerNoticeShown) else { return }
        showEarlyBuyerNotice = true
    }

    // MARK: - Helpers

    /// States where the person is waiting on the sheet for a result.
    private static func isWaiting(_ state: PurchaseState) -> Bool {
        state == .pending || state == .finishing || state == .purchasing
    }

    private static func finalReason(_ error: Error) -> String? {
        guard let relayError = error as? RelayError else { return nil }
        guard let reason = relayError.reason as String?,
              finalReasons.contains(reason) else { return nil }
        return reason
    }

    /// The most useful rejection to show when several proofs were refused.
    private static func rank(_ reason: String) -> Int {
        switch reason {
        case "too_many_inboxes": return 3
        case "wrong_account": return 2
        default: return 1
        }
    }

    private static func copy(forReason reason: String, restoring: Bool) -> String {
        switch reason {
        case "too_many_inboxes": return PurchaseCopy.tooManyInboxes
        case "wrong_account": return PurchaseCopy.wrongAccount
        default: return restoring ? PurchaseCopy.nothingToRestore : PurchaseCopy.failed
        }
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError { return true }
        return false
    }
}
