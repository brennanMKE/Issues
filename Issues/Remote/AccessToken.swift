import Foundation
import CryptoKit

#if os(macOS)
import Security
#endif

/// Errors surfaced from `AccessToken` operations. Keychain failures pass the
/// raw `OSStatus` through so callers can render or log it meaningfully.
enum AccessTokenError: Error, Equatable {
    case notFound
    case expired
    /// The on-disk JSON blob is unreadable. Should only happen if the
    /// Keychain item is tampered with externally; the next `generate` /
    /// `revoke` call will overwrite it.
    case malformed
    case keychain(OSStatus)
}

/// One issued access token. The plaintext is shown once at generation time
/// and discarded — the host stores only `hash` (SHA-256 of the plaintext).
nonisolated struct TokenRecord: Codable, Equatable, Sendable {
    /// SHA-256 of the plaintext token. 32 bytes.
    var hash: Data
    /// User label, e.g. "MacBook Air".
    var name: String
    var createdAt: Date
    var expiresAt: Date?
    var lastUsedAt: Date?
    /// Best-effort identifier of the most recent caller (IP / reverse-DNS).
    var lastUsedFrom: String?
}

/// The full token database stored as a single JSON-encoded Keychain item.
/// One item, many records — see `RemoteAccess.md` and #0078.
nonisolated struct TokenDatabase: Codable, Equatable, Sendable {
    var records: [TokenRecord]

    static let empty = TokenDatabase(records: [])
}

#if os(macOS)

/// Phase 1 host-side token store. Single Keychain item, JSON blob.
///
/// Public methods accept a `service:` parameter that defaults to the
/// production service name. Tests pass a unique value to isolate from the
/// live database and clean up via `deleteAll(service:)` afterwards.
enum AccessToken {

    /// Production Keychain service name. Tests override.
    nonisolated static let defaultService = "co.sstools.Issues.RemoteAccess.HostTokens"
    nonisolated private static let account = "default"
    nonisolated private static let plaintextPrefix = "iat_"
    /// 32 random bytes → 43 base64url chars (no padding) → 47 chars total
    /// including the `iat_` prefix.
    static let plaintextLength = 47

    // MARK: - Public API

    /// Result of `generate(name:expiresAt:identity:)` — the canonical
    /// token-creation entry point post-#0113. The user sees `combined`;
    /// internal callers (tests, settings UI) can read the parts.
    struct Generated: Equatable {
        /// `iat_<43>.<64-hex>` — what the user copies. ~108 characters.
        let combined: String
        /// Just the bearer plaintext (`iat_…`), 47 chars.
        let plaintext: String
        /// Just the host cert fingerprint (64-hex), at the moment of mint.
        let fingerprint: String
        /// Token-database record (host stores only the hash + metadata).
        let record: TokenRecord
    }

    /// Mints a new token bound to the given host identity (#0113). The
    /// plaintext is the only place the raw bearer is ever returned;
    /// the fingerprint comes from the live identity and isn't recorded
    /// per-token (it's a host property, not a token property).
    static func generate(
        name: String,
        expiresAt: Date?,
        identity: RemoteServerIdentity,
        service: String = defaultService
    ) throws -> Generated {
        let raw = try randomBytes(32)
        let plaintext = plaintextPrefix + raw.base64URLEncodedString()
        let hash = sha256(of: plaintext)
        let record = TokenRecord(
            hash: hash,
            name: name,
            createdAt: Date(),
            expiresAt: expiresAt,
            lastUsedAt: nil,
            lastUsedFrom: nil
        )
        var db = try load(service: service)
        db.records.append(record)
        try save(db, service: service)
        return Generated(
            combined: "\(plaintext).\(identity.fingerprintHex)",
            plaintext: plaintext,
            fingerprint: identity.fingerprintHex,
            record: record
        )
    }

    /// Legacy overload for callers that don't have an identity yet
    /// (test code paths from #0078). Returns the bare plaintext +
    /// record; production token-creation must go through the
    /// identity-aware overload above so the user-facing token carries
    /// the fingerprint.
    static func generate(
        name: String,
        expiresAt: Date?,
        service: String = defaultService
    ) throws -> (plaintext: String, record: TokenRecord) {
        let raw = try randomBytes(32)
        let plaintext = plaintextPrefix + raw.base64URLEncodedString()
        let hash = sha256(of: plaintext)
        let record = TokenRecord(
            hash: hash,
            name: name,
            createdAt: Date(),
            expiresAt: expiresAt,
            lastUsedAt: nil,
            lastUsedFrom: nil
        )
        var db = try load(service: service)
        db.records.append(record)
        try save(db, service: service)
        return (plaintext, record)
    }

    /// Parses a combined `iat_<43>.<64-hex>` token. Returns the two
    /// halves on success; throws `.malformed` for any deviation
    /// (missing `.`, wrong-length plaintext, wrong-length / non-hex
    /// fingerprint). Used by the viewer paste step (#0096/#0114).
    static func parseCombined(_ raw: String) throws -> (plaintext: String, fingerprint: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw AccessTokenError.malformed }
        let plaintext = parts[0]
        let fingerprint = parts[1]
        guard plaintext.hasPrefix(plaintextPrefix), plaintext.count == plaintextLength else {
            throw AccessTokenError.malformed
        }
        guard fingerprint.count == 64,
              fingerprint.allSatisfy({ ($0.isNumber) || ("a"..."f").contains($0) }) else {
            throw AccessTokenError.malformed
        }
        return (plaintext, fingerprint)
    }

    /// Removes the record matching `hash`. No-op (no error) if the hash
    /// isn't present — revoking an already-gone token is idempotent.
    static func revoke(hash: Data, service: String = defaultService) throws {
        var db = try load(service: service)
        let before = db.records.count
        db.records.removeAll { $0.hash == hash }
        if db.records.count != before {
            try save(db, service: service)
        }
    }

    static func list(service: String = defaultService) throws -> [TokenRecord] {
        try load(service: service).records
    }

    /// Validates an incoming bearer token. Hashes the plaintext, looks up
    /// the record, and checks `expiresAt`. Does **not** update
    /// `lastUsedAt` — call `touch` for that so the read path stays cheap.
    /// `from peer` is currently unused; it's kept in the signature so
    /// callers don't need to change when we wire `touch` into the auth
    /// middleware (#0079).
    static func validate(
        plaintext: String,
        from peer: String?,
        service: String = defaultService
    ) throws -> TokenRecord {
        _ = peer
        let hash = sha256(of: plaintext)
        let db = try load(service: service)
        guard let record = db.records.first(where: { $0.hash == hash }) else {
            throw AccessTokenError.notFound
        }
        if let expiresAt = record.expiresAt, expiresAt < Date() {
            throw AccessTokenError.expired
        }
        return record
    }

    /// Updates `lastUsedAt` / `lastUsedFrom` on the matching record.
    /// Throws `.notFound` if no record matches the hash.
    ///
    /// `nonisolated` so callers (e.g. `RemoteServer`'s `Task.detached`
    /// bookkeeping path) can run this off the MainActor without an actor
    /// hop. The body only touches Keychain + JSON via the nonisolated
    /// `load` / `save` helpers.
    nonisolated static func touch(
        hash: Data,
        from peer: String?,
        service: String = defaultService
    ) throws {
        var db = try load(service: service)
        guard let idx = db.records.firstIndex(where: { $0.hash == hash }) else {
            throw AccessTokenError.notFound
        }
        db.records[idx].lastUsedAt = Date()
        db.records[idx].lastUsedFrom = peer
        try save(db, service: service)
    }

    /// Wipes the entire database for the given service. Intended for test
    /// teardown and an eventual "Sign out all viewers" UI affordance in
    /// #0084.
    static func deleteAll(service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccessTokenError.keychain(status)
        }
    }

    // MARK: - Hashing / RNG

    private static func sha256(of plaintext: String) -> Data {
        Data(SHA256.hash(data: Data(plaintext.utf8)))
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else {
            throw AccessTokenError.keychain(status)
        }
        return Data(bytes)
    }

    // MARK: - Keychain backing store

    /// JSON encoder/decoder use the default `.deferredToDate` strategy
    /// (Double seconds since the 2001 reference date) so generation and
    /// last-used timestamps round-trip exactly. The blob is opaque storage,
    /// not user-visible JSON, so ISO8601 readability isn't worth the
    /// fractional-second precision loss.
    nonisolated private static let jsonEncoder = JSONEncoder()
    nonisolated private static let jsonDecoder = JSONDecoder()

    nonisolated private static func load(service: String) throws -> TokenDatabase {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .empty
        }
        guard status == errSecSuccess else {
            throw AccessTokenError.keychain(status)
        }
        guard let data = item as? Data else {
            return .empty
        }
        do {
            return try jsonDecoder.decode(TokenDatabase.self, from: data)
        } catch {
            throw AccessTokenError.malformed
        }
    }

    nonisolated private static func save(_ db: TokenDatabase, service: String) throws {
        let data = try jsonEncoder.encode(db)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AccessTokenError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AccessTokenError.keychain(addStatus)
        }
    }
}

private extension Data {
    /// Base64url, no padding — RFC 4648 §5.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#endif
