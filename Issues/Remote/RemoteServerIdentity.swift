import Foundation
import CryptoKit
import os.log

#if os(macOS)
import Security

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "RemoteServerIdentity")

/// Errors surfaced from `RemoteServerIdentity` cert/Keychain operations.
enum RemoteServerIdentityError: Error, Equatable {
    case keyGenerationFailed(String)
    case signingFailed(String)
    case certificateConstructionFailed
    case identityConstructionFailed(OSStatus)
    case keychain(OSStatus)
}

/// The host's stable TLS identity: a P-256 ECDSA private key + a self-signed
/// X.509 v3 leaf certificate, persisted together as a Keychain identity item.
/// The fingerprint is SHA-256 of the DER-encoded leaf (matches the convention
/// used by `openssl x509 -fingerprint -sha256`).
///
/// See #0112 for the full spec.
struct RemoteServerIdentity {
    let secIdentity: SecIdentity
    let certificate: SecCertificate
    let fingerprintSHA256: Data        // 32 bytes
    var fingerprintHex: String {
        fingerprintSHA256.map { String(format: "%02x", $0) }.joined()
    }
}

extension RemoteServerIdentity {

    /// Production Keychain label. Tests pass a unique suffix to isolate.
    static let defaultLabel = "Issues Remote Access Host Identity"

    // MARK: - Lookup

    /// Loads the persisted identity by `label`. Returns nil if not present.
    ///
    /// We locate the private key via its `kSecAttrApplicationTag` (derived
    /// from `label`), then enumerate certificates with the matching cert
    /// label and verify each one's public key against the private key's
    /// public-key bytes. The first cert whose public key matches the
    /// private key is bundled into a `SecIdentity` via
    /// `SecIdentityCreateWithCertificate` and returned.
    ///
    /// This avoids `kSecClassIdentity` enumeration entirely. Apple's
    /// identity index is eventually-consistent on macOS — immediately
    /// after `SecItemAdd`, an identity query may not surface the new
    /// pair. Direct key+cert lookup short-circuits that lag.
    static func load(label: String = defaultLabel) throws -> RemoteServerIdentity? {
        let tag = applicationTag(for: label)
        // Look up the private key by tag. We deliberately scope only on
        // `kSecClass` + `kSecAttrApplicationTag` here — extra filters like
        // `kSecAttrKeyType` are inconsistent enough on macOS that they
        // sometimes turn a successful match into `errSecItemNotFound`
        // depending on which keychain backing store stamped the original
        // key. The tag is unique-per-label and is what we set on generation.
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var keyItem: CFTypeRef?
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyItem)
        if keyStatus == errSecItemNotFound {
            return nil
        }
        guard keyStatus == errSecSuccess, let cfKey = keyItem else {
            if keyStatus == errSecSuccess { return nil }
            throw RemoteServerIdentityError.keychain(keyStatus)
        }
        let privateKey = cfKey as! SecKey
        let publicKey = try copyPublicKey(privateKey: privateKey)
        let publicKeyData = try copyPublicKeyDER(publicKey: publicKey)

        // Enumerate all certificates and pick the one whose public key
        // matches `publicKeyData`. Cert-by-label lookup is unreliable
        // (keychain index lag), so we skip the filter and post-filter by
        // public key — which is the truly unique identifier.
        //
        // Retry briefly: under parallel test load, macOS's keychain
        // index sometimes lags `SecItemAdd` by a few milliseconds. Up
        // to ~150 ms total wall-clock is fine for our purposes (the
        // production path calls `load(label:)` once at app launch).
        let certificates = try findCertificatesMatching(publicKeyData: publicKeyData)
        for certificate in certificates {
            var identityRef: SecIdentity?
            let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identityRef)
            guard identityStatus == errSecSuccess, let identity = identityRef else {
                throw RemoteServerIdentityError.identityConstructionFailed(identityStatus)
            }
            let fingerprint = sha256(of: SecCertificateCopyData(certificate) as Data)
            return RemoteServerIdentity(
                secIdentity: identity,
                certificate: certificate,
                fingerprintSHA256: fingerprint
            )
        }
        return nil
    }

    /// Enumerate all certificates in the user's default keychain search list
    /// and return those whose public key matches `publicKeyData`. Retries
    /// once with a short backoff to absorb the keychain index lag macOS
    /// exhibits immediately after `SecItemAdd`.
    private static func findCertificatesMatching(publicKeyData: Data) throws -> [SecCertificate] {
        for attempt in 0..<2 {
            if attempt > 0 {
                // 50 ms — small enough not to be noticeable, large enough
                // that the keychain index catches up on the slowest CI run
                // we've observed.
                Thread.sleep(forTimeInterval: 0.05)
            }
            let certQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecReturnRef as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ]
            var certItem: CFTypeRef?
            let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)
            if certStatus == errSecItemNotFound {
                continue
            }
            guard certStatus == errSecSuccess, let rawCerts = certItem else {
                if certStatus == errSecSuccess { continue }
                throw RemoteServerIdentityError.keychain(certStatus)
            }
            let certificates: [SecCertificate] = (rawCerts as! [AnyObject]).compactMap { entry -> SecCertificate? in
                let cf = entry as CFTypeRef
                guard CFGetTypeID(cf) == SecCertificateGetTypeID() else { return nil }
                return (cf as! SecCertificate)
            }
            let matches = certificates.filter { certificate in
                guard let certPublicKey = SecCertificateCopyKey(certificate) else { return false }
                var error: Unmanaged<CFError>?
                guard let certPublicKeyData = SecKeyCopyExternalRepresentation(certPublicKey, &error) as Data? else { return false }
                return certPublicKeyData == publicKeyData
            }
            if !matches.isEmpty {
                return matches
            }
        }
        return []
    }

    // MARK: - Generation

    /// Generates a new P-256 ECDSA private key, builds a minimal self-signed
    /// X.509 v3 cert (CN=Issues Host, EKU=serverAuth, 10-year validity, no
    /// SAN), persists the key+cert as a Keychain identity under `label`, and
    /// returns the resulting `RemoteServerIdentity`.
    ///
    /// If an identity already exists under `label`, it is replaced.
    @discardableResult
    static func generate(label: String = defaultLabel) throws -> RemoteServerIdentity {
        // Wipe any prior identity for this label first so a regenerate truly
        // replaces (the spec mandates this for rotation).
        try deleteAll(label: label)

        let privateKey = try createP256PrivateKey(label: label)
        let publicKey = try copyPublicKey(privateKey: privateKey)
        let publicKeyBitString = try copyECP256PublicKeyBitString(publicKey: publicKey)

        let serial = try randomSerial(byteCount: 20)
        let now = Date()
        let notBefore = now.addingTimeInterval(-300) // small skew tolerance
        let notAfter = now.addingTimeInterval(60 * 60 * 24 * 365 * 10) // 10 years

        let tbs = X509Builder.tbsCertificate(
            serial: serial,
            subjectCommonName: "Issues Host",
            notBefore: notBefore,
            notAfter: notAfter,
            subjectPublicKeyBitString: publicKeyBitString
        )

        // Sign the TBS with ECDSA-SHA256. The algorithm produces an
        // X9.62 DER-encoded ECDSA signature, which is what X.509 expects.
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            tbs as CFData,
            &signError
        ) as Data? else {
            let message = signError?.takeRetainedValue().localizedDescription ?? "unknown"
            throw RemoteServerIdentityError.signingFailed(message)
        }

        let certDER = X509Builder.wrapCertificate(tbs: tbs, signature: signature)

        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw RemoteServerIdentityError.certificateConstructionFailed
        }

        // Add the certificate to the Keychain alongside the key. With both
        // present, SecItemCopyMatching on kSecClassIdentity can bundle them
        // for subsequent `load(label:)` calls.
        try addCertificate(certificate, label: label)

        // Construct the identity directly rather than re-querying. The
        // keychain's identity index is eventually-consistent on macOS —
        // immediately after `SecItemAdd`, an enumeration may not surface
        // the new pair. `SecIdentityCreateWithCertificate` looks up the
        // matching private key in the keychain by the cert's public key,
        // which is the load-bearing relationship we just established.
        var identityRef: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identityRef)
        guard identityStatus == errSecSuccess, let secIdentity = identityRef else {
            throw RemoteServerIdentityError.identityConstructionFailed(identityStatus)
        }
        let fingerprint = sha256(of: SecCertificateCopyData(certificate) as Data)
        let identity = RemoteServerIdentity(
            secIdentity: secIdentity,
            certificate: certificate,
            fingerprintSHA256: fingerprint
        )

        logger.notice("RemoteServerIdentity generated label=\(label, privacy: .public) fingerprint=\(identity.fingerprintHex, privacy: .public)")
        return identity
    }

    // MARK: - Cleanup

    /// Wipes every Keychain entry associated with `label`: the bundled
    /// identity, the standalone certificate, and the standalone private
    /// key (matched by the same label / application tag). Intended for
    /// tests and #0115's "rotate cert" affordance.
    ///
    /// We find and delete the matching certificate(s) first, then the
    /// private key, then issue a sweeping identity delete. `load(label:)`
    /// gates on a cert/public-key match, so removing certs first means
    /// any post-delete `load` returns nil even if macOS's key index
    /// hasn't caught up to the key delete yet.
    static func deleteAll(label: String = defaultLabel) throws {
        let tag = applicationTag(for: label)

        // First, find the public key associated with our tag — if any.
        // We use it below to scrub any certificate whose public key
        // matches, regardless of how/where it was labeled.
        var publicKeyData: Data? = nil
        let keyLookupQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var keyItem: CFTypeRef?
        let keyLookupStatus = SecItemCopyMatching(keyLookupQuery as CFDictionary, &keyItem)
        if keyLookupStatus == errSecSuccess, let cfKey = keyItem {
            let privateKey = cfKey as! SecKey
            if let publicKey = SecKeyCopyPublicKey(privateKey) {
                publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
            }
        }

        // Delete certificates: any with our label, plus any whose public
        // key matches our key. The latter sweep covers cases where the
        // cert's label attribute isn't searchable in the current keychain
        // index state (macOS quirk).
        let certByLabelQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]
        let certByLabelStatus = SecItemDelete(certByLabelQuery as CFDictionary)
        guard certByLabelStatus == errSecSuccess || certByLabelStatus == errSecItemNotFound else {
            throw RemoteServerIdentityError.keychain(certByLabelStatus)
        }
        if let publicKeyData {
            // Enumerate all certs, drop the ones matching our key.
            let allCertsQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecReturnRef as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ]
            var allCertsItem: CFTypeRef?
            let allCertsStatus = SecItemCopyMatching(allCertsQuery as CFDictionary, &allCertsItem)
            if allCertsStatus == errSecSuccess, let raw = allCertsItem,
               let entries = raw as? [AnyObject] {
                for entry in entries {
                    let cf = entry as CFTypeRef
                    guard CFGetTypeID(cf) == SecCertificateGetTypeID() else { continue }
                    let cert = cf as! SecCertificate
                    guard let certPublicKey = SecCertificateCopyKey(cert) else { continue }
                    guard let certPublicKeyData = SecKeyCopyExternalRepresentation(certPublicKey, nil) as Data? else { continue }
                    if certPublicKeyData == publicKeyData {
                        let q: [String: Any] = [
                            kSecClass as String: kSecClassCertificate,
                            kSecValueRef as String: cert
                        ]
                        let s = SecItemDelete(q as CFDictionary)
                        if s != errSecSuccess && s != errSecItemNotFound {
                            throw RemoteServerIdentityError.keychain(s)
                        }
                    }
                }
            }
        }

        // Now delete the private key.
        let keyDeleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag
        ]
        let keyStatus = SecItemDelete(keyDeleteQuery as CFDictionary)
        guard keyStatus == errSecSuccess || keyStatus == errSecItemNotFound else {
            throw RemoteServerIdentityError.keychain(keyStatus)
        }

        // Final sweep: identity delete by label, in case the prior two
        // deletes left a phantom.
        let identityDeleteQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label
        ]
        let identityStatus = SecItemDelete(identityDeleteQuery as CFDictionary)
        guard identityStatus == errSecSuccess || identityStatus == errSecItemNotFound else {
            throw RemoteServerIdentityError.keychain(identityStatus)
        }
    }

    // MARK: - Internals

    private static func sha256(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func randomSerial(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, base)
        }
        guard status == errSecSuccess else {
            throw RemoteServerIdentityError.keychain(status)
        }
        // X.509 serial must be a positive ASN.1 INTEGER. Force the high bit
        // off so DER encoding doesn't have to prepend a zero byte.
        bytes[0] &= 0x7F
        // Avoid an all-zero leading byte by guaranteeing at least one set bit
        // in the top nibble; cosmetic, but keeps `openssl x509 -text` happy.
        if bytes[0] == 0 { bytes[0] = 0x01 }
        return Data(bytes)
    }

    /// Stable per-label discriminator for the private key. We use this as
    /// `kSecAttrApplicationTag` because it's the only key-class attribute
    /// macOS reliably filters on; `kSecAttrLabel` is sometimes ignored on
    /// search queries for keys/identities.
    private static func applicationTag(for label: String) -> Data {
        Data(label.utf8)
    }

    private static func createP256PrivateKey(label: String) throws -> SecKey {
        // We let the key persist in the Keychain so SecItemCopyMatching on
        // kSecClassIdentity will pair it with the certificate we add below.
        // `kSecAttrIsPermanent = true` is the load-bearing attribute.
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: label,
            kSecAttrApplicationTag as String: applicationTag(for: label),
            kSecAttrSynchronizable as String: false
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw RemoteServerIdentityError.keyGenerationFailed(message)
        }
        return key
    }

    private static func copyPublicKey(privateKey: SecKey) throws -> SecKey {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw RemoteServerIdentityError.keyGenerationFailed("SecKeyCopyPublicKey returned nil")
        }
        return publicKey
    }

    /// External representation of the public key. For EC keys on Apple
    /// platforms this is the uncompressed X9.63 form: `0x04 || X || Y`
    /// (65 bytes for P-256).
    private static func copyPublicKeyDER(publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw RemoteServerIdentityError.keyGenerationFailed(message)
        }
        return data
    }

    /// Returns the X9.63 uncompressed P-256 public key bytes wrapped in an
    /// ASN.1 BIT STRING (with the leading 0 unused-bits byte), suitable for
    /// inclusion in `SubjectPublicKeyInfo.subjectPublicKey`.
    private static func copyECP256PublicKeyBitString(publicKey: SecKey) throws -> Data {
        let raw = try copyPublicKeyDER(publicKey: publicKey)
        // Apple returns the 65-byte uncompressed form 0x04 || X(32) || Y(32).
        guard raw.count == 65, raw.first == 0x04 else {
            throw RemoteServerIdentityError.keyGenerationFailed("unexpected EC public key shape (\(raw.count) bytes)")
        }
        return raw
    }

    private static func addCertificate(_ certificate: SecCertificate, label: String) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        // Duplicate is unexpected because deleteAll runs first, but treat it
        // as success — the cert is already in place.
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw RemoteServerIdentityError.keychain(status)
        }
    }
}

// MARK: - X.509 / ASN.1 DER builder
//
// Minimal hand-rolled ASN.1 DER encoder targeting the subset of X.509 v3 the
// host needs:
//   Certificate ::= SEQUENCE {
//     tbsCertificate       TBSCertificate,
//     signatureAlgorithm   AlgorithmIdentifier,
//     signatureValue       BIT STRING
//   }
//   TBSCertificate ::= SEQUENCE {
//     version             [0] EXPLICIT Version DEFAULT v1, -- we emit v3
//     serialNumber        CertificateSerialNumber,
//     signature           AlgorithmIdentifier,
//     issuer              Name,
//     validity            Validity,
//     subject             Name,
//     subjectPublicKeyInfo SubjectPublicKeyInfo,
//     extensions          [3] EXPLICIT Extensions
//   }
//
// The encoder is intentionally narrow — only the tags and lengths we actually
// emit, nothing generic.

enum DERTag {
    static let integer: UInt8 = 0x02
    static let bitString: UInt8 = 0x03
    static let octetString: UInt8 = 0x04
    static let null: UInt8 = 0x05
    static let objectIdentifier: UInt8 = 0x06
    static let utf8String: UInt8 = 0x0C
    static let printableString: UInt8 = 0x13
    static let utcTime: UInt8 = 0x17
    static let generalizedTime: UInt8 = 0x18
    static let sequence: UInt8 = 0x30
    static let set: UInt8 = 0x31
    /// Context-specific, constructed, tag 0 ([0]).
    static let contextSpecific0: UInt8 = 0xA0
    /// Context-specific, constructed, tag 3 ([3]).
    static let contextSpecific3: UInt8 = 0xA3
}

enum DER {

    /// Encode an ASN.1 length octet block (definite form).
    static func length(_ count: Int) -> Data {
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        // Long form: 0x80 | numBytes, then big-endian byte count.
        var n = count
        var bytes: [UInt8] = []
        while n > 0 {
            bytes.insert(UInt8(n & 0xFF), at: 0)
            n >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    static func wrap(tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    /// Encode a non-negative big-endian integer. ASN.1 INTEGERs are signed,
    /// so we prepend 0x00 if the high bit of the first byte is set.
    static func integer(_ bytes: Data) -> Data {
        var trimmed = bytes
        // Strip leading zeros (but leave at least one byte).
        while trimmed.count > 1 && trimmed.first == 0 {
            trimmed.removeFirst()
        }
        var payload = trimmed
        if let first = payload.first, first & 0x80 != 0 {
            payload = Data([0x00]) + payload
        }
        return wrap(tag: DERTag.integer, payload)
    }

    static func integer(_ value: Int) -> Data {
        var v = value
        var bytes: [UInt8] = []
        if v == 0 {
            bytes = [0]
        } else {
            while v > 0 {
                bytes.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            }
        }
        return integer(Data(bytes))
    }

    static func objectIdentifier(_ components: [UInt64]) -> Data {
        precondition(components.count >= 2)
        var bytes: [UInt8] = []
        let first = components[0] * 40 + components[1]
        bytes.append(contentsOf: base128(first))
        for c in components.dropFirst(2) {
            bytes.append(contentsOf: base128(c))
        }
        return wrap(tag: DERTag.objectIdentifier, Data(bytes))
    }

    /// Variable-length base-128 with continuation bit, used for OID arcs.
    private static func base128(_ value: UInt64) -> [UInt8] {
        if value == 0 { return [0] }
        var out: [UInt8] = []
        var v = value
        while v > 0 {
            out.insert(UInt8(v & 0x7F), at: 0)
            v >>= 7
        }
        for i in 0..<(out.count - 1) {
            out[i] |= 0x80
        }
        return out
    }

    static func bitString(_ payload: Data, unusedBits: UInt8 = 0) -> Data {
        var data = Data([unusedBits])
        data.append(payload)
        return wrap(tag: DERTag.bitString, data)
    }

    static func octetString(_ payload: Data) -> Data {
        wrap(tag: DERTag.octetString, payload)
    }

    static func utf8String(_ value: String) -> Data {
        wrap(tag: DERTag.utf8String, Data(value.utf8))
    }

    static func printableString(_ value: String) -> Data {
        wrap(tag: DERTag.printableString, Data(value.utf8))
    }

    static func null() -> Data {
        Data([DERTag.null, 0x00])
    }

    static func sequence(_ children: [Data]) -> Data {
        var content = Data()
        for c in children { content.append(c) }
        return wrap(tag: DERTag.sequence, content)
    }

    static func set(_ children: [Data]) -> Data {
        var content = Data()
        for c in children { content.append(c) }
        return wrap(tag: DERTag.set, content)
    }

    static func explicitTag(_ tag: UInt8, _ content: Data) -> Data {
        wrap(tag: tag, content)
    }

    /// Date in `YYMMDDhhmmssZ` UTCTime form (valid 1950-2049). For dates
    /// outside that range, X.509 mandates GeneralizedTime — we choose at
    /// build time based on the year.
    static func time(_ date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        if year >= 1950 && year < 2050 {
            let yy = year % 100
            let s = String(format: "%02d%02d%02d%02d%02d%02dZ", yy, month, day, hour, minute, second)
            return wrap(tag: DERTag.utcTime, Data(s.utf8))
        } else {
            let s = String(format: "%04d%02d%02d%02d%02d%02dZ", year, month, day, hour, minute, second)
            return wrap(tag: DERTag.generalizedTime, Data(s.utf8))
        }
    }
}

enum X509Builder {

    /// OID: 1.2.840.10045.4.3.2 ecdsa-with-SHA256
    private static let oidEcdsaWithSHA256: [UInt64] = [1, 2, 840, 10045, 4, 3, 2]
    /// OID: 1.2.840.10045.2.1 id-ecPublicKey
    private static let oidEcPublicKey: [UInt64] = [1, 2, 840, 10045, 2, 1]
    /// OID: 1.2.840.10045.3.1.7 prime256v1 (a.k.a. P-256)
    private static let oidP256NamedCurve: [UInt64] = [1, 2, 840, 10045, 3, 1, 7]
    /// OID: 2.5.4.3 commonName
    private static let oidCommonName: [UInt64] = [2, 5, 4, 3]
    /// OID: 2.5.29.19 basicConstraints
    private static let oidBasicConstraints: [UInt64] = [2, 5, 29, 19]
    /// OID: 2.5.29.15 keyUsage
    private static let oidKeyUsage: [UInt64] = [2, 5, 29, 15]
    /// OID: 2.5.29.37 extKeyUsage
    private static let oidExtKeyUsage: [UInt64] = [2, 5, 29, 37]
    /// OID: 1.3.6.1.5.5.7.3.1 id-kp-serverAuth
    private static let oidServerAuth: [UInt64] = [1, 3, 6, 1, 5, 5, 7, 3, 1]

    /// AlgorithmIdentifier for ECDSA with SHA-256. Parameters are ABSENT
    /// (not NULL) for ECDSA signatures per RFC 5758 §3.2.
    static func ecdsaSHA256AlgorithmIdentifier() -> Data {
        DER.sequence([
            DER.objectIdentifier(oidEcdsaWithSHA256)
        ])
    }

    /// AlgorithmIdentifier for an EC public key on the P-256 curve.
    static func ecP256AlgorithmIdentifier() -> Data {
        DER.sequence([
            DER.objectIdentifier(oidEcPublicKey),
            DER.objectIdentifier(oidP256NamedCurve)
        ])
    }

    /// X.501 Name with a single CN RDN.
    static func name(commonName: String) -> Data {
        let attribute = DER.sequence([
            DER.objectIdentifier(oidCommonName),
            DER.utf8String(commonName)
        ])
        let rdn = DER.set([attribute])
        return DER.sequence([rdn])
    }

    static func subjectPublicKeyInfo(publicKeyBitString: Data) -> Data {
        DER.sequence([
            ecP256AlgorithmIdentifier(),
            DER.bitString(publicKeyBitString)
        ])
    }

    /// Builds the TBSCertificate DER bytes ready for signing.
    static func tbsCertificate(
        serial: Data,
        subjectCommonName: String,
        notBefore: Date,
        notAfter: Date,
        subjectPublicKeyBitString: Data
    ) -> Data {
        // [0] EXPLICIT version v3 (INTEGER 2)
        let versionExplicit = DER.explicitTag(DERTag.contextSpecific0, DER.integer(2))
        let serialDER = DER.integer(serial)
        let signatureAlg = ecdsaSHA256AlgorithmIdentifier()
        let issuer = name(commonName: subjectCommonName)
        let validity = DER.sequence([
            DER.time(notBefore),
            DER.time(notAfter)
        ])
        let subject = issuer
        let spki = subjectPublicKeyInfo(publicKeyBitString: subjectPublicKeyBitString)
        let extensions = self.extensions()

        return DER.sequence([
            versionExplicit,
            serialDER,
            signatureAlg,
            issuer,
            validity,
            subject,
            spki,
            extensions
        ])
    }

    /// Returns `Certificate` (the outer SEQUENCE) given a TBS and its
    /// ECDSA-DER signature.
    static func wrapCertificate(tbs: Data, signature: Data) -> Data {
        DER.sequence([
            tbs,
            ecdsaSHA256AlgorithmIdentifier(),
            DER.bitString(signature)
        ])
    }

    // MARK: - Extensions

    /// [3] EXPLICIT Extensions block containing BasicConstraints, KeyUsage,
    /// and ExtendedKeyUsage. All three are marked critical except EKU which
    /// is non-critical to match common practice.
    private static func extensions() -> Data {
        let basicConstraints = extensionEntry(
            oid: oidBasicConstraints,
            critical: true,
            value: DER.sequence([]) // CA = FALSE (default), no path length
        )
        let keyUsage = extensionEntry(
            oid: oidKeyUsage,
            critical: true,
            value: keyUsageDigitalSignature()
        )
        let extKeyUsage = extensionEntry(
            oid: oidExtKeyUsage,
            critical: false,
            value: DER.sequence([
                DER.objectIdentifier(oidServerAuth)
            ])
        )
        let extensions = DER.sequence([basicConstraints, keyUsage, extKeyUsage])
        return DER.explicitTag(DERTag.contextSpecific3, extensions)
    }

    private static func extensionEntry(oid: [UInt64], critical: Bool, value: Data) -> Data {
        var children: [Data] = [DER.objectIdentifier(oid)]
        if critical {
            // BOOLEAN TRUE
            children.append(Data([0x01, 0x01, 0xFF]))
        }
        children.append(DER.octetString(value))
        return DER.sequence(children)
    }

    /// KeyUsage BIT STRING with `digitalSignature` (bit 0) set.
    /// Encoded as BIT STRING with 7 unused bits, payload `0x80`.
    private static func keyUsageDigitalSignature() -> Data {
        DER.bitString(Data([0x80]), unusedBits: 7)
    }
}

#endif
