import Testing
import Foundation
import CryptoKit
@testable import IssuesCore

#if os(macOS)
import Security

/// Tests for #0112: P-256 self-signed cert generation, Keychain persistence,
/// and SHA-256 fingerprint exposure.
///
/// Each test isolates via a unique Keychain label (UUID suffix) and cleans
/// up in defer. The suite is `.serialized` because Apple's Security
/// framework serializes parallel Keychain mutations behind a process-wide
/// lock anyway; explicit serialization avoids the timing/visibility races
/// we see under Swift Testing's default parallelism (xnu's Keychain
/// trust cache appears to lag a `SecItemDelete` by tens of milliseconds).
@Suite(.serialized)
@MainActor
struct RemoteServerIdentityTests {

    private static func uniqueLabel() -> String {
        "Issues Remote Access Host Identity Test \(UUID().uuidString)"
    }

    @Test func generateProducesFingerprintAndIdentity() throws {
        let label = Self.uniqueLabel()
        defer { try? RemoteServerIdentity.deleteAll(label: label) }

        let identity = try RemoteServerIdentity.generate(label: label)

        #expect(identity.fingerprintSHA256.count == 32)
        #expect(identity.fingerprintHex.count == 64)
        // Lowercase hex only.
        let hexCharSet = Set("0123456789abcdef")
        #expect(identity.fingerprintHex.allSatisfy { hexCharSet.contains($0) })

        // The bundled SecIdentity must yield both a private key and a
        // certificate.
        var privateKey: SecKey?
        let keyStatus = SecIdentityCopyPrivateKey(identity.secIdentity, &privateKey)
        #expect(keyStatus == errSecSuccess)
        #expect(privateKey != nil)

        // Sanity-check the fingerprint matches SHA-256(DER cert bytes).
        let derData = SecCertificateCopyData(identity.certificate) as Data
        let recomputed = sha256(derData)
        #expect(recomputed == identity.fingerprintSHA256)
    }

    @Test func loadAfterGenerateReturnsSameIdentity() throws {
        let label = Self.uniqueLabel()
        defer { try? RemoteServerIdentity.deleteAll(label: label) }

        let generated = try RemoteServerIdentity.generate(label: label)
        let loaded = try RemoteServerIdentity.load(label: label)
        let unwrapped = try #require(loaded)
        #expect(unwrapped.fingerprintHex == generated.fingerprintHex)
        #expect(unwrapped.fingerprintSHA256 == generated.fingerprintSHA256)
    }

    @Test func loadOnMissingReturnsNil() throws {
        let label = Self.uniqueLabel()
        // No generate; verify a fresh label has no entry.
        let result = try RemoteServerIdentity.load(label: label)
        #expect(result == nil)
    }

    @Test func generateAgainReplacesIdentity() throws {
        let label = Self.uniqueLabel()
        defer { try? RemoteServerIdentity.deleteAll(label: label) }

        let first = try RemoteServerIdentity.generate(label: label)
        let second = try RemoteServerIdentity.generate(label: label)
        #expect(first.fingerprintHex != second.fingerprintHex)

        // After regenerate, load() returns the second identity (not the
        // first one).
        let loaded = try RemoteServerIdentity.load(label: label)
        let unwrapped = try #require(loaded)
        #expect(unwrapped.fingerprintHex == second.fingerprintHex)
    }

    @Test func deleteAllRemovesIdentity() throws {
        let label = Self.uniqueLabel()
        _ = try RemoteServerIdentity.generate(label: label)
        try RemoteServerIdentity.deleteAll(label: label)
        let loaded = try RemoteServerIdentity.load(label: label)
        #expect(loaded == nil)
    }

    // MARK: - Helpers

    private func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

#endif
