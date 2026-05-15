import Foundation
import CryptoKit
import os.log

#if os(macOS) || os(iOS)

nonisolated private let pinLogger = Logger(subsystem: Logging.subsystem, category: "PinnedHostSessionDelegate")

/// `URLSessionDelegate` that pins the host's TLS cert by SHA-256
/// fingerprint (#0114). Used by `RemoteClient` (#0094) and
/// `RemoteWebSocket` (#0102) so the self-signed cert produced by the
/// host (#0112) is acceptable as long as its fingerprint matches what
/// the viewer pinned at paste time (#0113).
///
/// Implements both `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)`
/// and `URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:)`
/// because `URLSessionWebSocketTask` dispatches challenges to the task
/// delegate on some macOS releases.
public final class PinnedHostSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {

    /// Lowercase 64-char hex of the expected SHA-256 fingerprint of the
    /// host's leaf certificate.
    public let expectedFingerprint: String

    public init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint.lowercased()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        evaluate(challenge: challenge, completionHandler: completionHandler)
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        evaluate(challenge: challenge, completionHandler: completionHandler)
    }

    // MARK: - Pin logic

    private func evaluate(
        challenge: URLAuthenticationChallenge,
        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            // Anything that isn't a server-trust challenge (Basic, NTLM, …)
            // shouldn't happen on our endpoints; fall back to the default
            // so we don't accidentally drop a useful auth path.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let presented = Self.leafCertificateFingerprint(from: trust) else {
            pinLogger.warning("no leaf cert in server trust — rejecting")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if presented == expectedFingerprint {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            pinLogger.warning("fingerprint mismatch — expected=\(self.expectedFingerprint, privacy: .public) presented=\(presented, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Computes the SHA-256 fingerprint (lowercase 64-char hex) of the
    /// leaf certificate in the given `SecTrust`. Returns nil if the chain
    /// is empty or the leaf can't be read. Exposed `internal` for tests.
    public static func leafCertificateFingerprint(from trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return nil
        }
        let der = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: der)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

#endif
