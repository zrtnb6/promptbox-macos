import Foundation
import Security

/// WebDAV 密码只存系统钥匙串，永不写入 JSON、永不进入导出文件或同步文件。
enum Keychain {
    private static let service = "com.zrtnb.promptbox.webdav"

    private static func account(for url: String, username: String) -> String {
        "\(url)|\(username)"
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(url: String, username: String, password: String) {
        let acct = account(for: url, username: username)
        let query = baseQuery(acct)
        let attrs: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        } else {
            var add = query
            for (k, v) in attrs { add[k] = v }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func load(url: String, username: String) -> String? {
        let acct = account(for: url, username: username)
        var query = baseQuery(acct)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(url: String, username: String) {
        SecItemDelete(baseQuery(account(for: url, username: username)) as CFDictionary)
    }
}
