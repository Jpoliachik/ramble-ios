//
//  WatchConnection.swift
//  watch Watch App
//
//  The watch's connection to Ramble's server, as the iPhone hands it over
//  in the WatchConnectivity application context: a watch token (rmbw_…),
//  the relay base URL, and whether the account is unlocked. The token lives
//  in the Keychain. A token the phone replaces is revoked on the server
//  (relay-api.md); only the last one is kept, to name in `replaces`.
//

import Combine
import Foundation
import Security

@MainActor
final class WatchConnection: ObservableObject {
    static let shared = WatchConnection()

    static let defaultBaseURL = URL(string: "https://ramble-transcription-proxy.jpoliachik.workers.dev")!

    /// The token uploads use. Nil until the iPhone connects the watch.
    @Published private(set) var token: String?
    /// The server answered 401 to the current token: it was replaced or
    /// revoked, and the iPhone needs to connect the watch again.
    @Published private(set) var tokenRejected: Bool
    @Published private(set) var baseURL: URL
    @Published private(set) var unlocked: Bool

    /// Can upload right now, as far as the watch knows.
    var isConnected: Bool { token != nil && !tokenRejected }

    /// What to send as `replaces` in needsConnection: the current token, or
    /// the last one the watch had.
    var tokenToReplace: String? { token ?? WatchKeychain.read(Self.lastTokenAccount) }

    private static let tokenAccount = "watchToken"
    private static let lastTokenAccount = "lastWatchToken"
    /// Replaced tokens kept by older builds. Deleted at launch.
    private static let oldTokensAccount = "previousWatchTokens"
    private static let rejectedKey = "watchTokenRejected"
    private static let baseURLKey = "relayBaseURL"
    private static let unlockedKey = "accountUnlocked"

    private init() {
        token = WatchKeychain.read(Self.tokenAccount)
        tokenRejected = UserDefaults.standard.bool(forKey: Self.rejectedKey)
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey).flatMap(URL.init(string:)) ?? Self.defaultBaseURL
        unlocked = UserDefaults.standard.bool(forKey: Self.unlockedKey)
        WatchKeychain.delete(Self.oldTokensAccount)
    }

    /// Returns true when the token changed (a new connection).
    @discardableResult
    func setToken(_ newToken: String?) -> Bool {
        let cleaned = newToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (cleaned?.isEmpty ?? true) ? nil : cleaned
        guard next != token else { return false }
        if let previous = token {
            WatchKeychain.write(previous, account: Self.lastTokenAccount)
        }
        token = next
        if let next {
            WatchKeychain.write(next, account: Self.tokenAccount)
        } else {
            WatchKeychain.delete(Self.tokenAccount)
        }
        setRejected(false)
        return true
    }

    /// A 401 for the token a request carried. Only the current token's 401
    /// counts; an answer to a token already replaced changes nothing.
    func markRejected(token rejected: String?) {
        guard let rejected, rejected == token else { return }
        setRejected(true)
    }

    func setBaseURL(_ text: String?) {
        let url = text.flatMap(URL.init(string:)) ?? Self.defaultBaseURL
        guard url != baseURL else { return }
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.baseURLKey)
    }

    /// Returns true when the account just became unlocked.
    @discardableResult
    func setUnlocked(_ value: Bool) -> Bool {
        guard value != unlocked else { return false }
        unlocked = value
        UserDefaults.standard.set(value, forKey: Self.unlockedKey)
        return value
    }

    private func setRejected(_ value: Bool) {
        guard value != tokenRejected else { return }
        tokenRejected = value
        UserDefaults.standard.set(value, forKey: Self.rejectedKey)
    }
}

/// Generic-password items, readable after first unlock so background
/// passes can upload while the watch is locked on the wrist.
enum WatchKeychain {
    private static let service = "dev.goodloop.ramble.watch"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            _ = SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
