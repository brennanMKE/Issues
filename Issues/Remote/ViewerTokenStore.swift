import Foundation

#if os(macOS) || os(iOS)
import Security

/// Viewer-side Keychain helpers for bearer tokens (#0095). Much simpler
/// than the host side (#0078): one item per host, plaintext token stored,
/// no metadata beyond what `kSecClassGenericPassword` already provides.
/// Storage is per-host so revoking a single host is a clean atomic
/// `SecItemDelete`.
///
/// Cross-platform — iOS will reuse this verbatim when the viewer target
/// lands in #0108. The Keychain access group stays implicit (per-app
/// group) until/unless we want shared access; the spec says no iCloud
/// sync and no cross-device sharing in v1.
enum ViewerTokenStore {

    /// Production Keychain service. Tests override via the underscore
    /// methods below.
    static let defaultService = "co.sstools.Issues.RemoteAccess.ViewerTokens"

    enum ViewerTokenError: Error, Equatable {
        case keychain(OSStatus)
        case malformed
    }

    // MARK: - Public API

    static func store(token: String, forHost hostId: String, service: String = defaultService) throws {
        let data = Data(token.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId
        ]
        // Update first, then add. Mirrors the pattern from AccessToken so
        // updates don't create duplicate items.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ViewerTokenError.keychain(updateStatus)
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ViewerTokenError.keychain(addStatus)
        }
    }

    static func token(forHost hostId: String, service: String = defaultService) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ViewerTokenError.keychain(status)
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ViewerTokenError.malformed
        }
        return token
    }

    static func remove(forHost hostId: String, service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ViewerTokenError.keychain(status)
        }
    }

    /// Lists every `hostId` with a stored token under the given service. Used
    /// for the "Forget all hosts" entry in viewer settings (#0096 / #0098).
    static func allHosts(service: String = defaultService) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw ViewerTokenError.keychain(status)
        }
        guard let array = items as? [[String: Any]] else { return [] }
        return array.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    /// Wipes every viewer-token item under the given service. Intended for
    /// test teardown and an eventual "Forget all hosts" affordance.
    static func deleteAll(service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ViewerTokenError.keychain(status)
        }
    }
}

#endif
