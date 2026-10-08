import Foundation
import Security

enum Keychain {
    private static func query(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.coffer.webdav", kSecAttrAccount as String: account] }
    static func set(_ password: String, account: String) throws {
        var attributes = query(account)
        let data = Data(password.utf8)
        let status = SecItemUpdate(attributes as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw FileProviderError.other("Couldn't save the password (\(added)).") }
        } else if status != errSecSuccess { throw FileProviderError.other("Couldn't save the password (\(status)).") }
    }
    static func get(account: String) -> String {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func delete(account: String) { SecItemDelete(query(account) as CFDictionary) }
}
