//
//  AccountService.swift
//  Ramble
//
//  Last known account state (free notes, unlock) from the relay.
//  The server decides; the app shows what it last heard and persists it, so
//  Settings and Home read sensibly offline.
//

import Combine
import Foundation

@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    private static let storageKey = "relayAccount"

    @Published private(set) var account: RelayAccount?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(RelayAccount.self, from: data) {
            account = stored
        }
    }

    var isUnlocked: Bool { account?.unlocked == true }

    /// GET /account. Quiet on failure: the last known state stays.
    func refresh() async {
        guard Consent.hasConsented, RelayService.shared.hasInbox, !KeychainService.isLocked else { return }
        guard let fresh = try? await RelayService.shared.fetchAccount() else { return }
        apply(fresh)
    }

    /// Store, publish, and tell the watch when `unlocked` changes. Safe to
    /// call more than once with the same state.
    func apply(_ newAccount: RelayAccount) {
        let merged = newAccount
        let previous = account
        guard merged != previous else { return }
        account = merged
        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }

        let becameUnlocked = merged.unlocked && previous?.unlocked != true
        if merged.unlocked != previous?.unlocked {
            PhoneConnectivityService.shared.pushApplicationContext()
        }
        if becameUnlocked {
            PhoneConnectivityService.shared.sendUnlocked()
        }
        // Unlocked, or free notes back (a permanent failure refunds one):
        // held phone notes go now, oldest first.
        if merged.unlocked || merged.freeNotesRemaining > 0 {
            UploadQueueService.shared.releaseUnlockHolds()
        }
    }

    /// POST /entitlement with ["signed_transaction": jws] or ["app_transaction": jws].
    /// Throws RelayError; a 403 carries its `reason`.
    func submitEntitlement(_ body: [String: String]) async throws -> RelayAccount {
        let fresh = try await RelayService.shared.submitEntitlement(body)
        apply(fresh)
        return fresh
    }

    /// The upload queue just heard 402 free_notes_used.
    func noteFreeNotesUsed() {
        guard var current = account, !current.unlocked, current.freeNotesRemaining != 0 else { return }
        current.freeNotesRemaining = 0
        apply(current)
    }
}
