//
//  AccountService.swift
//  Ramble
//
//  Last known account state (free notes, unlock, fair use) from the relay.
//  Stub: the signatures are the contract between the phone and purchase code.
//

import Combine
import Foundation

@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    @Published private(set) var account: RelayAccount?

    private init() {}

    /// GET /account.
    func refresh() async {}

    /// Store, publish, and tell the watch when `unlocked` changes.
    func apply(_ account: RelayAccount) {
        self.account = account
    }

    /// POST /entitlement with ["signed_transaction": jws] or ["app_transaction": jws].
    func submitEntitlement(_ body: [String: String]) async throws -> RelayAccount {
        throw RelayError.network("Not implemented")
    }
}
