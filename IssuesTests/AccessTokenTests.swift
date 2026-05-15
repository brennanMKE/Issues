import Testing
import IssuesCore
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for `AccessToken` (#0078). Each test uses a unique Keychain
/// service name so concurrent runs don't collide and so the production
/// host-token database is never touched. `deleteAll` is called in a
/// `defer` to guarantee cleanup.
struct AccessTokenTests {

    private static func uniqueService() -> String {
        "co.sstools.Issues.RemoteAccess.HostTokens.Test.\(UUID().uuidString)"
    }

    // MARK: - Format

    @Test func generateProducesExpectedFormat() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let (plaintext, record) = try AccessToken.generate(name: "Mac Mini", expiresAt: nil, service: service)

        #expect(plaintext.hasPrefix("iat_"))
        #expect(plaintext.count == AccessToken.plaintextLength)
        #expect(record.name == "Mac Mini")
        #expect(record.hash.count == 32)
        #expect(record.expiresAt == nil)
        #expect(record.lastUsedAt == nil)
        #expect(record.lastUsedFrom == nil)
    }

    // MARK: - Generate → validate

    @Test func generateThenValidateReturnsRecord() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let (plaintext, record) = try AccessToken.generate(name: "Air", expiresAt: nil, service: service)
        let validated = try AccessToken.validate(plaintext: plaintext, from: nil, service: service)

        #expect(validated == record)
    }

    @Test func validateUnknownPlaintextThrowsNotFound() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        // Database is empty for this service.
        do {
            _ = try AccessToken.validate(plaintext: "iat_doesnotexist", from: nil, service: service)
            Issue.record("validate should have thrown")
        } catch let error as AccessTokenError {
            #expect(error == .notFound)
        }
    }

    // MARK: - Revoke

    @Test func revokeRemovesRecordSoValidateThrowsNotFound() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let (plaintext, record) = try AccessToken.generate(name: "Air", expiresAt: nil, service: service)
        try AccessToken.revoke(hash: record.hash, service: service)

        do {
            _ = try AccessToken.validate(plaintext: plaintext, from: nil, service: service)
            Issue.record("validate should have thrown after revoke")
        } catch let error as AccessTokenError {
            #expect(error == .notFound)
        }
        let remaining = try AccessToken.list(service: service)
        #expect(remaining.isEmpty)
    }

    @Test func revokeIsIdempotentOnMissingHash() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }
        try AccessToken.revoke(hash: Data(repeating: 0, count: 32), service: service) // no-op
    }

    // MARK: - Expiration

    @Test func expiredTokenThrowsExpired() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let pastDate = Date(timeIntervalSinceNow: -60)
        let (plaintext, _) = try AccessToken.generate(name: "Old", expiresAt: pastDate, service: service)

        do {
            _ = try AccessToken.validate(plaintext: plaintext, from: nil, service: service)
            Issue.record("validate should have thrown for expired token")
        } catch let error as AccessTokenError {
            #expect(error == .expired)
        }
    }

    @Test func futureExpiryStillValid() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let future = Date(timeIntervalSinceNow: 3600)
        let (plaintext, record) = try AccessToken.generate(name: "Soon", expiresAt: future, service: service)

        let validated = try AccessToken.validate(plaintext: plaintext, from: nil, service: service)
        #expect(validated.hash == record.hash)
    }

    // MARK: - Touch

    @Test func touchUpdatesLastUsedAtAndLastUsedFrom() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let (_, record) = try AccessToken.generate(name: "Air", expiresAt: nil, service: service)
        let before = Date()
        try AccessToken.touch(hash: record.hash, from: "192.168.1.42", service: service)

        let listed = try AccessToken.list(service: service)
        #expect(listed.count == 1)
        let updated = try #require(listed.first)
        #expect(updated.lastUsedFrom == "192.168.1.42")
        let lastUsed = try #require(updated.lastUsedAt)
        #expect(lastUsed >= before)
    }

    @Test func touchOnUnknownHashThrowsNotFound() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }
        do {
            try AccessToken.touch(hash: Data(repeating: 0, count: 32), from: nil, service: service)
            Issue.record("touch should have thrown for unknown hash")
        } catch let error as AccessTokenError {
            #expect(error == .notFound)
        }
    }

    // MARK: - Multiple records

    @Test func generatingSecondTokenPreservesFirst() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        let (plaintextA, recordA) = try AccessToken.generate(name: "Air", expiresAt: nil, service: service)
        let (plaintextB, recordB) = try AccessToken.generate(name: "Mini", expiresAt: nil, service: service)

        #expect(plaintextA != plaintextB)
        #expect(recordA.hash != recordB.hash)

        // Both validate.
        let validatedA = try AccessToken.validate(plaintext: plaintextA, from: nil, service: service)
        let validatedB = try AccessToken.validate(plaintext: plaintextB, from: nil, service: service)
        #expect(validatedA.name == "Air")
        #expect(validatedB.name == "Mini")

        let listed = try AccessToken.list(service: service)
        #expect(listed.count == 2)
    }

    // MARK: - Persistence across calls

    @Test func recordsPersistAcrossLoadCalls() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }

        _ = try AccessToken.generate(name: "Air", expiresAt: nil, service: service)
        _ = try AccessToken.generate(name: "Mini", expiresAt: nil, service: service)

        // Independent `list` call hits the Keychain again, exercising the
        // load → decode path on a populated database.
        let names = try AccessToken.list(service: service).map { $0.name }
        #expect(Set(names) == Set(["Air", "Mini"]))
    }

    // MARK: - Combined token format (#0113)

    @Test func parseCombinedHappyPath() throws {
        let token = "iat_" + String(repeating: "a", count: 43)
        let fingerprint = String(repeating: "0", count: 64)
        let combined = "\(token).\(fingerprint)"
        let parsed = try AccessToken.parseCombined(combined)
        #expect(parsed.plaintext == token)
        #expect(parsed.fingerprint == fingerprint)
    }

    @Test func parseCombinedTrimsWhitespace() throws {
        let token = "iat_" + String(repeating: "a", count: 43)
        let fingerprint = String(repeating: "0", count: 64)
        let combined = "  \(token).\(fingerprint)\n"
        let parsed = try AccessToken.parseCombined(combined)
        #expect(parsed.plaintext == token)
        #expect(parsed.fingerprint == fingerprint)
    }

    @Test func parseCombinedRejectsBareToken() {
        let token = "iat_" + String(repeating: "a", count: 43)
        do {
            _ = try AccessToken.parseCombined(token)
            Issue.record("expected malformed for bare token")
        } catch let error as AccessTokenError {
            #expect(error == .malformed)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func parseCombinedRejectsBadFingerprintLength() {
        let token = "iat_" + String(repeating: "a", count: 43)
        let shortFingerprint = String(repeating: "0", count: 63)
        do {
            _ = try AccessToken.parseCombined("\(token).\(shortFingerprint)")
            Issue.record("expected malformed for short fingerprint")
        } catch let error as AccessTokenError {
            #expect(error == .malformed)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func parseCombinedRejectsNonHexFingerprint() {
        let token = "iat_" + String(repeating: "a", count: 43)
        let bad = String(repeating: "z", count: 64)
        do {
            _ = try AccessToken.parseCombined("\(token).\(bad)")
            Issue.record("expected malformed for non-hex fingerprint")
        } catch let error as AccessTokenError {
            #expect(error == .malformed)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}

#endif
