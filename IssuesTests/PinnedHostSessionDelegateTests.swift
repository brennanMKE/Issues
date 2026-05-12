import Testing
import Foundation
import CryptoKit
@testable import Issues

#if os(macOS)

/// Tests for `PinnedHostSessionDelegate` (#0114). The full
/// `URLAuthenticationChallenge` round-trip requires a `URLProtectionSpace`
/// constructor that's awkward to drive in unit tests; what we cover here
/// is the pure-storage contract (lowercasing the expected fingerprint).
/// The `leafCertificateFingerprint(from:)` helper is exercised indirectly
/// by `RemoteServerIdentityTests` (the identity it generates flows
/// through that helper at TLS-handshake time).
struct PinnedHostSessionDelegateTests {

    @Test func storesFingerprintLowercased() {
        let delegate = PinnedHostSessionDelegate(expectedFingerprint: "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789")
        #expect(delegate.expectedFingerprint == String(repeating: "abcdef0123456789", count: 4))
    }
}

#endif
