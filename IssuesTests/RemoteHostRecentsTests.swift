import Testing
import Foundation
@testable import Issues

/// Tests for `RemoteHostRecents` (#0091). Each test uses a fresh
/// `UserDefaults` suite so writes don't leak across runs or contaminate
/// the standard suite.
struct RemoteHostRecentsTests {

    private static func uniqueDefaults() -> UserDefaults {
        let name = "RemoteHostRecentsTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func listIsEmptyOnFreshDefaults() {
        let defaults = Self.uniqueDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description) }
        #expect(RemoteHostRecents.list(defaults: defaults).isEmpty)
    }

    @Test func upsertAddsAndRoundTrips() {
        let defaults = Self.uniqueDefaults()
        let identity = RemoteHostIdentity(
            host: "100.74.12.5",
            port: 51823,
            displayName: "Brennan's Mac",
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        )
        RemoteHostRecents.upsert(identity, defaults: defaults)
        let listed = RemoteHostRecents.list(defaults: defaults)
        #expect(listed.count == 1)
        #expect(listed.first?.host == "100.74.12.5")
        #expect(listed.first?.port == 51823)
        #expect(listed.first?.displayName == "Brennan's Mac")
    }

    @Test func upsertDedupesByHostPortId() {
        let defaults = Self.uniqueDefaults()
        let first = RemoteHostIdentity(
            host: "mac-mini.local",
            port: 51823,
            displayName: "Mini",
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = RemoteHostIdentity(
            host: "mac-mini.local",
            port: 51823,
            displayName: "Mac Mini 2",
            lastUsedAt: Date(timeIntervalSince1970: 2_000)
        )
        RemoteHostRecents.upsert(first, defaults: defaults)
        RemoteHostRecents.upsert(second, defaults: defaults)
        let listed = RemoteHostRecents.list(defaults: defaults)
        #expect(listed.count == 1)
        #expect(listed.first?.displayName == "Mac Mini 2")
    }

    @Test func upsertWithNilDisplayNamePreservesExistingName() {
        // A 401 probe shouldn't blow away the name we learned from a
        // previous successful connect.
        let defaults = Self.uniqueDefaults()
        let withName = RemoteHostIdentity(
            host: "mac-a.local",
            port: 51823,
            displayName: "Mac A",
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        )
        let withoutName = RemoteHostIdentity(
            host: "mac-a.local",
            port: 51823,
            displayName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 2_000)
        )
        RemoteHostRecents.upsert(withName, defaults: defaults)
        RemoteHostRecents.upsert(withoutName, defaults: defaults)
        let listed = RemoteHostRecents.list(defaults: defaults)
        #expect(listed.first?.displayName == "Mac A")
    }

    @Test func forgetRemovesEntry() {
        let defaults = Self.uniqueDefaults()
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: "alpha",
            port: 51823,
            displayName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        ), defaults: defaults)
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: "beta",
            port: 51823,
            displayName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 2_000)
        ), defaults: defaults)
        RemoteHostRecents.forget(id: "alpha:51823", defaults: defaults)
        let listed = RemoteHostRecents.list(defaults: defaults)
        #expect(listed.count == 1)
        #expect(listed.first?.host == "beta")
    }

    @Test func forgetMissingIdIsIdempotent() {
        let defaults = Self.uniqueDefaults()
        RemoteHostRecents.forget(id: "no-such:1234", defaults: defaults)
        #expect(RemoteHostRecents.list(defaults: defaults).isEmpty)
    }

    @Test func listIsSortedByMostRecentFirst() {
        let defaults = Self.uniqueDefaults()
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: "old",
            port: 51823,
            displayName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        ), defaults: defaults)
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: "newer",
            port: 51823,
            displayName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 5_000)
        ), defaults: defaults)
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: "middle",
            port: 51823,
            displayName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 3_000)
        ), defaults: defaults)
        let listed = RemoteHostRecents.list(defaults: defaults)
        #expect(listed.map { $0.host } == ["newer", "middle", "old"])
    }
}
