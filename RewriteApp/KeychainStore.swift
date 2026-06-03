import Foundation
import Security

/// Minimal Keychain wrapper for secrets (Anthropic API key, hosted gateway token).
/// Values are never written to UserDefaults or logged.
enum KeychainStore {
    private static let service = "com.rewriteapp.apikey"

    // MARK: Generic account-keyed access

    static func set(_ value: String, account: String) {
        delete(account: account)
        guard !value.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Convenience (Anthropic API key — backward compatible)

    static func save(_ value: String) { set(value, account: "anthropic") }
    static func load() -> String? { get(account: "anthropic") }
    static func delete() { delete(account: "anthropic") }

    // MARK: Hosted gateway token

    static func saveHostedToken(_ value: String) { set(value, account: "hostedToken") }
    static func loadHostedToken() -> String? { get(account: "hostedToken") }
    static func deleteHostedToken() { delete(account: "hostedToken") }
}
