//
//  KeychainService.swift
//  Ramble
//

import Foundation
import Security

enum KeychainService {
    private static let service = "dev.goodloop.ramble"

    /// Readable after the first unlock post-boot, so background work (e.g. a
    /// watch recording reaching a locked phone) can read the relay inbox
    /// secret and App Attest key. The default, `WhenUnlocked`, blocks reads
    /// while the phone is locked. Not `ThisDeviceOnly`, so the inbox secret
    /// survives a backup restore onto a new phone; a restored App Attest key
    /// fails with `invalidKey` and is re-attested.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlock

    enum Lookup: Equatable {
        case found(String)
        case notFound
        /// The item exists but the phone is locked (before the first unlock
        /// after a reboot, or an item not yet migrated off `WhenUnlocked`).
        /// Callers must wait, not treat it as missing and regenerate it.
        case locked
    }

    static func lookup(forKey key: String) -> Lookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecInteractionNotAllowed { return .locked }
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return .notFound
        }
        return .found(string)
    }

    /// The stored value, or nil when it's missing or the phone is locked.
    /// Use `lookup(forKey:)` when those two cases need different handling.
    static func string(forKey key: String) -> String? {
        if case .found(let value) = lookup(forKey: key) { return value }
        return nil
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func setString(_ value: String, forKey key: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = accessibility
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    // MARK: - Migration

    private static let accessibilityMigratedKey = "keychainAccessibilityMigrated"

    /// Older installs wrote every item with the default `WhenUnlocked`
    /// accessibility, so a watch recording that reached a locked phone couldn't
    /// read the relay inbox secret or App Attest key and was silently skipped.
    /// This moves all of Ramble's items to `AfterFirstUnlock` in one update.
    /// Call it only while protected data is available (the phone is unlocked):
    /// locked items can't be updated, and the flag stops later retries.
    static func migrateAccessibilityIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: accessibilityMigratedKey) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: accessibility
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            defaults.set(true, forKey: accessibilityMigratedKey)
        }
    }
}
