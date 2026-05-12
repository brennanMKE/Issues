import Testing
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for `ViewerTokenStore` (#0095). Each test uses a unique Keychain
/// service name and cleans up via `deleteAll(service:)`.
struct ViewerTokenStoreTests {

    private static func uniqueService() -> String {
        "co.sstools.Issues.RemoteAccess.ViewerTokens.Test.\(UUID().uuidString)"
    }

    @Test func storeAndReadRoundTrips() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        try ViewerTokenStore.store(token: "iat_abc", forHost: "mac-a", service: service)
        let read = try ViewerTokenStore.token(forHost: "mac-a", service: service)
        #expect(read == "iat_abc")
    }

    @Test func readingMissingHostReturnsNil() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        let read = try ViewerTokenStore.token(forHost: "no-such-host", service: service)
        #expect(read == nil)
    }

    @Test func storeReplacesExistingTokenForSameHost() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        try ViewerTokenStore.store(token: "iat_first", forHost: "mac-a", service: service)
        try ViewerTokenStore.store(token: "iat_second", forHost: "mac-a", service: service)
        let read = try ViewerTokenStore.token(forHost: "mac-a", service: service)
        #expect(read == "iat_second")
        let all = try ViewerTokenStore.allHosts(service: service)
        #expect(all == ["mac-a"])
    }

    @Test func removeDropsTheTokenForOneHostOnly() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        try ViewerTokenStore.store(token: "iat_a", forHost: "mac-a", service: service)
        try ViewerTokenStore.store(token: "iat_b", forHost: "mac-b", service: service)
        try ViewerTokenStore.remove(forHost: "mac-a", service: service)
        #expect((try ViewerTokenStore.token(forHost: "mac-a", service: service)) == nil)
        #expect((try ViewerTokenStore.token(forHost: "mac-b", service: service)) == "iat_b")
    }

    @Test func removingMissingHostIsIdempotent() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        try ViewerTokenStore.remove(forHost: "no-such-host", service: service)
    }

    @Test func allHostsListsEveryStoredHost() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        try ViewerTokenStore.store(token: "iat_a", forHost: "alpha", service: service)
        try ViewerTokenStore.store(token: "iat_b", forHost: "beta", service: service)
        try ViewerTokenStore.store(token: "iat_c", forHost: "gamma", service: service)
        let hosts = try ViewerTokenStore.allHosts(service: service)
        #expect(hosts == ["alpha", "beta", "gamma"])
    }

    // MARK: - Token + fingerprint (#0113)

    @Test func storeWithFingerprintRoundTrips() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        try ViewerTokenStore.store(
            token: "iat_xyz",
            fingerprint: "a3f1e0c082b41d77",
            forHost: "mac-a",
            service: service
        )
        let entry = try ViewerTokenStore.entry(forHost: "mac-a", service: service)
        #expect(entry?.token == "iat_xyz")
        #expect(entry?.fingerprint == "a3f1e0c082b41d77")
    }

    @Test func entryForMissingHostReturnsNil() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        let entry = try ViewerTokenStore.entry(forHost: "no-such", service: service)
        #expect(entry == nil)
    }

    @Test func legacyBareTokenReadsAsEntryWithEmptyFingerprint() throws {
        let service = Self.uniqueService()
        defer { try? ViewerTokenStore.deleteAll(service: service) }
        // Use the legacy single-arg store(). It now goes through the
        // new path with empty fingerprint, but the on-Keychain blob
        // is a JSON object with `fingerprint: ""`.
        try ViewerTokenStore.store(token: "iat_legacy", forHost: "old-host", service: service)
        let entry = try ViewerTokenStore.entry(forHost: "old-host", service: service)
        #expect(entry?.token == "iat_legacy")
        #expect(entry?.fingerprint == "")
        // The legacy single-string accessor still returns the bearer.
        #expect((try ViewerTokenStore.token(forHost: "old-host", service: service)) == "iat_legacy")
    }
}

#endif
