//
//  KeychainService.swift
//  Ramble
//

import Foundation
import Security

enum KeychainService {
    private static let service = "dev.goodloop.ramble"

    /// Readable while the device is locked, as long as it has been unlocked once
    /// since boot. The default (`WhenUnlocked`) is wrong here: Ramble reads the
    /// webhook secret from background work that runs on a locked phone (a watch
    /// recording arriving, a queued webhook, a Live Activity button), where the
    /// item would simply be unavailable.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlock

    /// Why a read didn't return a value. "Not there" and "couldn't be read" have to
    /// be told apart: treating a failed read as absence is what let a locked device
    /// overwrite the stored secret with a freshly generated one.
    enum ReadResult {
        case found(String)
        case notFound
        case unavailable(OSStatus)
    }

    static func read(forKey key: String) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                return .unavailable(status)
            }
            return .found(string)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable(status)
        }
    }

    static func string(forKey key: String) -> String? {
        if case .found(let value) = read(forKey: key) { return value }
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
        // Accessibility is set on update too, so an item written by an older build
        // is migrated in place rather than staying unreadable while locked.
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
}
