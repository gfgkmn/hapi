import Foundation
import Security

/// Simple Keychain wrapper for storing the HAPI access token securely.
enum Keychain {
    private static let service = "run.hapi.client"
    private static let accessTokenKey = "accessToken"
    private static let baseURLKey = "baseURL"

    static func saveAccessToken(_ token: String) {
        save(key: accessTokenKey, value: token)
    }

    static func loadAccessToken() -> String? {
        load(key: accessTokenKey)
    }

    static func deleteAccessToken() {
        delete(key: accessTokenKey)
    }

    static func saveBaseURL(_ url: String) {
        save(key: baseURLKey, value: url)
    }

    static func loadBaseURL() -> String? {
        load(key: baseURLKey)
    }

    // MARK: - Private

    private static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [CFString: Any] = query.merging([kSecValueData: data]) { $1 }
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
