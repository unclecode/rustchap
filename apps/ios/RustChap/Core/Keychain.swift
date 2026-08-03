// Minimal Keychain wrapper + the device credentials stored through it.
// The Keychain outlives the app's container — delete and reinstall RustChap
// and the device token is still there, which is what makes progress recovery
// (Milestone 3) work without any account.

import Foundation
import Security

enum Keychain {
    private static let service = "dev.rustchap.RustChap"

    static func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(base.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The anonymous device identity, Keychain-backed. Read directly by APIClient
/// (auth header) and written by SyncService after registration.
enum DeviceCredentials {
    static var deviceId: String? {
        get { Keychain.string(for: "device_id") }
        set {
            if let newValue { Keychain.set(newValue, for: "device_id") } else { Keychain.delete("device_id") }
        }
    }

    static var token: String? {
        get { Keychain.string(for: "device_token") }
        set {
            if let newValue { Keychain.set(newValue, for: "device_token") } else { Keychain.delete("device_token") }
        }
    }
}
