import Foundation
import Security

/// Minimal generic-password Keychain wrapper for secrets at rest — the Supabase
/// session (refresh token) and the Canvas access token. Mirrors the Mac app's
/// `GoogleKeychain` pattern and works identically on macOS and iOS through the
/// Security framework (no extra entitlement over what the app already ships).
///
/// Service names follow the app's `com.atlas.Atlas.*` convention.
public enum KeychainStore {

    public enum Service {
        public static let supabase = "com.atlas.Atlas.supabase"
        public static let canvas   = "com.atlas.Atlas.canvas"
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    public static func save(_ data: Data, service: String, account: String) -> Bool {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        var add = baseQuery(service: service, account: account)
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public static func load(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    public static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}
