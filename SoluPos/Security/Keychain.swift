import Foundation
import Security

/// Envoltura mínima del Keychain (`kSecClassGenericPassword`). Los datos quedan
/// solo en este equipo (`WhenUnlockedThisDeviceOnly`), sin sincronizar con iCloud.
enum Keychain {
    private static func base(_ service: String, _ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    static func get(service: String, account: String) -> Data? {
        var q = base(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func set(_ data: Data, service: String, account: String) -> Bool {
        remove(service: service, account: account)
        var q = base(service, account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove(service: String, account: String) {
        SecItemDelete(base(service, account) as CFDictionary)
    }
}
