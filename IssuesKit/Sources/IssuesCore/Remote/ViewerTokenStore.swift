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
public enum ViewerTokenStore {

    /// Production Keychain service. Tests override via the underscore
    /// methods below.
    public static let defaultService = "co.sstools.Issues.RemoteAccess.ViewerTokens"

    public enum ViewerTokenError: Error, Equatable {
        case keychain(OSStatus)
        case malformed
    }

    /// Token + fingerprint stored per host (#0113). The viewer pins the
    /// fingerprint at paste time and matches it against the host's TLS
    /// cert at connect time (#0114). JSON-encoded as a Keychain blob.
    public struct Entry: Codable, Equatable, Sendable {
        public let token: String
        public let fingerprint: String

        public init(token: String, fingerprint: String) {
            self.token = token
            self.fingerprint = fingerprint
        }
    }

    // MARK: - Public API

    /// Stores the bearer alongside the cert fingerprint (#0113). Existing
    /// callers that only pass a token go through the legacy overload
    /// below and end up with `fingerprint = ""`.
    public static func store(token: String, fingerprint: String, forHost hostId: String, service: String = defaultService) throws {
        let entry = Entry(token: token, fingerprint: fingerprint)
        let data: Data
        do {
            data = try JSONEncoder().encode(entry)
        } catch {
            throw ViewerTokenError.malformed
        }
        try writeBlob(data, forHost: hostId, service: service)
    }

    /// Legacy overload (pre-#0113) — store just the bearer. Used by
    /// tests that don't care about the fingerprint and by the
    /// transitional code path while the TLS migration is in flight.
    /// On read, an entry written this way decodes with an empty
    /// fingerprint string.
    public static func store(token: String, forHost hostId: String, service: String = defaultService) throws {
        try store(token: token, fingerprint: "", forHost: hostId, service: service)
    }

    /// Reads the `(token, fingerprint)` pair for `hostId`. Returns nil
    /// when no entry exists. Legacy bare-token blobs (raw UTF-8 from a
    /// pre-#0113 build) decode with an empty fingerprint string so the
    /// caller can prompt the user to re-paste.
    public static func entry(forHost hostId: String, service: String = defaultService) throws -> Entry? {
        guard let data = try readBlob(forHost: hostId, service: service) else { return nil }
        if let decoded = try? JSONDecoder().decode(Entry.self, from: data) {
            return decoded
        }
        // Legacy fallback: the blob is just the bearer UTF-8 string.
        if let legacy = String(data: data, encoding: .utf8), legacy.hasPrefix("iat_") {
            return Entry(token: legacy, fingerprint: "")
        }
        throw ViewerTokenError.malformed
    }

    /// Legacy convenience that returns just the bearer string. Pre-#0113
    /// callers (TabsModel.restore, etc.) keep working; new callers
    /// should use `entry(forHost:)` so the fingerprint is available
    /// for the TLS pinning step in #0114.
    public static func token(forHost hostId: String, service: String = defaultService) throws -> String? {
        try entry(forHost: hostId, service: service)?.token
    }

    // MARK: - Private blob plumbing

    private static func writeBlob(_ data: Data, forHost hostId: String, service: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId
        ]
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

    private static func readBlob(forHost hostId: String, service: String) throws -> Data? {
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
        return item as? Data
    }

    public static func remove(forHost hostId: String, service: String = defaultService) throws {
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
    public static func allHosts(service: String = defaultService) throws -> [String] {
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
    public static func deleteAll(service: String = defaultService) throws {
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
