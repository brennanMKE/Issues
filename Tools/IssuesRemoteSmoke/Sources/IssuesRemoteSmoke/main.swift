import Foundation
import IssuesRemoteProtocol
import CryptoKit

// MARK: - Argument parsing

struct Options {
    var host: String?
    var token: String?
    /// Lowercase 64-char SHA-256 hex of the host's TLS cert. Required
    /// post-#0114 — the wire is TLS-only and the CLI pins via a custom
    /// URLSessionDelegate. The combined-token form (`iat_….<fp>`) can
    /// also be supplied via --token and the fingerprint will be split
    /// out automatically.
    var fingerprint: String?
    var folder: String?
    var issue: String?
    var verbose: Bool = false
}

func parseArgs(_ args: [String]) -> Options {
    var opts = Options()
    var i = 1
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--host":
            i += 1
            opts.host = i < args.count ? args[i] : nil
        case "--token":
            i += 1
            opts.token = i < args.count ? args[i] : nil
        case "--fingerprint":
            i += 1
            opts.fingerprint = i < args.count ? args[i] : nil
        case "--folder":
            i += 1
            opts.folder = i < args.count ? args[i] : nil
        case "--issue":
            i += 1
            opts.issue = i < args.count ? args[i] : nil
        case "--verbose", "-v":
            opts.verbose = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
            printUsage()
            exit(2)
        }
        i += 1
    }
    // Split a combined `iat_<43>.<64-hex>` --token into token + fingerprint
    // if the caller didn't pass them separately. Matches the format the
    // host's `AccessToken.generate` reveals (#0113).
    if let raw = opts.token, opts.fingerprint == nil, raw.contains(".") {
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, parts[0].hasPrefix("iat_"), parts[1].count == 64 {
            opts.token = parts[0]
            opts.fingerprint = parts[1]
        }
    }
    return opts
}

func printUsage() {
    let usage = """
    Usage: issues-remote-smoke --host HOST:PORT --token iat_…[.<fp>] [--fingerprint FP] [--folder ID] [--issue ID] [-v]

    Hits every v1 endpoint on a running Issues.app host and reports pass/fail.
    Connection uses HTTPS with cert-pinning per #0114; the host's self-signed
    cert is trusted iff its SHA-256 fingerprint matches the pinned value.

    Options:
      --host  HOST:PORT     required. e.g. 100.74.12.5:51823 or my-mac.local:51823
      --token iat_…         bearer token. May be the combined form
                            iat_<43>.<64-hex>; the fingerprint half is
                            extracted automatically.
      --fingerprint FP      64-hex SHA-256 of the host's TLS leaf cert.
                            Required unless --token is the combined form.
                            Falls back to $ISSUES_REMOTE_TOKEN for --token.
      --folder ID           optional. Defaults to the first folder /v1/folders returns.
      --issue  ID           optional. Defaults to the first issue.
      --verbose, -v         print full response bodies.
      --help, -h            this message.

    Exit status is 0 when every check passes, 1 otherwise.
    """
    print(usage)
}

// MARK: - Output

enum CheckOutcome {
    case ok(String)
    case fail(String)
    case skip(String)
}

final class Reporter {
    var verbose: Bool = false
    private(set) var failures: Int = 0
    private(set) var skipped: Int = 0
    private(set) var passed: Int = 0

    func report(_ name: String, _ outcome: CheckOutcome) {
        switch outcome {
        case .ok(let detail):
            passed += 1
            print("ok    \(name) — \(detail)")
        case .fail(let detail):
            failures += 1
            print("fail  \(name) — \(detail)")
        case .skip(let detail):
            skipped += 1
            print("skip  \(name) — \(detail)")
        }
    }

    func summary() -> Int {
        print("")
        print("\(passed) passed, \(failures) failed, \(skipped) skipped")
        return failures == 0 ? 0 : 1
    }
}

let reporter = Reporter()

// MARK: - HTTP

struct HTTPResult {
    var status: Int
    var headers: [AnyHashable: Any]
    var body: Data
}

enum HTTPError: Error, CustomStringConvertible {
    case transport(String)
    case noResponse
    case fingerprintMismatch

    var description: String {
        switch self {
        case .transport(let m): return m
        case .noResponse: return "no response"
        case .fingerprintMismatch: return "cert fingerprint did not match the pinned value"
        }
    }
}

/// Pins the host's TLS cert by SHA-256 fingerprint (matches the
/// app's `PinnedHostSessionDelegate`). Without pinning we'd need to
/// either trust the self-signed cert via the keychain or `curl -k`
/// equivalent — neither is appropriate for a verification tool.
final class PinnedSmokeDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let expected: String
    init(expected: String) { self.expected = expected.lowercased() }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        evaluate(challenge, completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        evaluate(challenge, completionHandler)
    }

    private func evaluate(_ challenge: URLAuthenticationChallenge,
                          _ completion: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completion(.cancelAuthenticationChallenge, nil)
            return
        }
        let der = SecCertificateCopyData(leaf) as Data
        let presented = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        if presented == expected {
            completion(.useCredential, URLCredential(trust: trust))
        } else {
            completion(.cancelAuthenticationChallenge, nil)
        }
    }
}

func get(_ url: URL, token: String?, session: URLSession) async throws -> HTTPResult {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    if let token, !token.isEmpty {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.noResponse }
        return HTTPResult(status: http.statusCode, headers: http.allHeaderFields, body: data)
    } catch let err as URLError {
        if err.code == .cancelled || err.code == .serverCertificateUntrusted {
            throw HTTPError.fingerprintMismatch
        }
        throw HTTPError.transport("\(err.localizedDescription) [\(err.code.rawValue)]")
    }
}

// MARK: - Checks

func baseURL(for host: String) -> URL? {
    URL(string: "https://\(host)")
}

@MainActor
func runChecks(opts: Options) async {
    guard let host = opts.host, let base = baseURL(for: host) else {
        reporter.report("host", .fail("missing or invalid --host"))
        return
    }
    guard let token = opts.token, !token.isEmpty else {
        reporter.report("token", .fail("missing --token (or $ISSUES_REMOTE_TOKEN)"))
        return
    }
    guard let fingerprint = opts.fingerprint, fingerprint.count == 64 else {
        reporter.report("fingerprint", .fail("missing --fingerprint (or combined --token form `iat_….<fp>`)"))
        return
    }

    let pinDelegate = PinnedSmokeDelegate(expected: fingerprint)
    let session = URLSession(configuration: .ephemeral, delegate: pinDelegate, delegateQueue: nil)

    // 1. /v1/host with valid token.
    var hostInfo: HostInfo?
    do {
        let result = try await get(base.appendingPathComponent("v1/host"), token: token, session: session)
        if result.status == 200,
           let info = try? RemoteProtocol.decoder.decode(HostInfo.self, from: result.body) {
            hostInfo = info
            reporter.report(
                "GET /v1/host",
                .ok("displayName=\"\(info.displayName)\" folderCount=\(info.folderCount) version=\(info.version)")
            )
        } else {
            reporter.report("GET /v1/host", .fail("status=\(result.status), body=\(prefix(result.body))"))
            return
        }
    } catch {
        reporter.report("GET /v1/host", .fail("\(error)"))
        return
    }

    // 2. /v1/host without token → 401 missing_token.
    do {
        let result = try await get(base.appendingPathComponent("v1/host"), token: nil, session: session)
        if result.status == 401, errorReason(in: result.body) == "missing_token" {
            reporter.report("GET /v1/host (no token)", .ok("401 missing_token"))
        } else {
            reporter.report(
                "GET /v1/host (no token)",
                .fail("expected 401 missing_token; got status=\(result.status), body=\(prefix(result.body))")
            )
        }
    } catch {
        reporter.report("GET /v1/host (no token)", .fail("\(error)"))
    }

    // 3. /v1/host with garbage token → 401 invalid_token.
    do {
        let result = try await get(base.appendingPathComponent("v1/host"), token: "iat_garbage", session: session)
        if result.status == 401, errorReason(in: result.body) == "invalid_token" {
            reporter.report("GET /v1/host (bad token)", .ok("401 invalid_token"))
        } else {
            reporter.report(
                "GET /v1/host (bad token)",
                .fail("expected 401 invalid_token; got status=\(result.status), body=\(prefix(result.body))")
            )
        }
    } catch {
        reporter.report("GET /v1/host (bad token)", .fail("\(error)"))
    }

    // 4. /v1/folders.
    var folders: [FolderInfo] = []
    do {
        let result = try await get(base.appendingPathComponent("v1/folders"), token: token, session: session)
        if result.status == 200,
           let list = try? RemoteProtocol.decoder.decode([FolderInfo].self, from: result.body) {
            folders = list
            let countMatches = (hostInfo?.folderCount).map { $0 == list.count } ?? true
            if countMatches {
                reporter.report("GET /v1/folders", .ok("\(list.count) folders"))
            } else {
                reporter.report(
                    "GET /v1/folders",
                    .fail("count \(list.count) doesn't match HostInfo.folderCount \(hostInfo?.folderCount ?? -1)")
                )
            }
        } else {
            reporter.report("GET /v1/folders", .fail("status=\(result.status), body=\(prefix(result.body))"))
            return
        }
    } catch {
        reporter.report("GET /v1/folders", .fail("\(error)"))
        return
    }

    if folders.isEmpty {
        reporter.report("GET /v1/folders/{id}", .skip("no folders to test"))
        return
    }

    // Pick folder.
    let folder: FolderInfo
    if let requested = opts.folder, let match = folders.first(where: { $0.id == requested }) {
        folder = match
    } else {
        folder = folders[0]
    }

    // 5. /v1/folders/<id>.
    do {
        let result = try await get(base.appendingPathComponent("v1/folders/\(folder.id)"), token: token, session: session)
        if result.status == 200,
           let info = try? RemoteProtocol.decoder.decode(FolderInfo.self, from: result.body),
           info.id == folder.id {
            reporter.report("GET /v1/folders/\(folder.id)", .ok("name=\"\(info.name)\""))
        } else {
            reporter.report("GET /v1/folders/\(folder.id)", .fail("status=\(result.status)"))
        }
    } catch {
        reporter.report("GET /v1/folders/\(folder.id)", .fail("\(error)"))
    }

    // 6. /v1/folders/<id>/issues.
    var metas: [IssueMetadata] = []
    do {
        let result = try await get(base.appendingPathComponent("v1/folders/\(folder.id)/issues"), token: token, session: session)
        if result.status == 200,
           let list = try? RemoteProtocol.decoder.decode([IssueMetadata].self, from: result.body) {
            metas = list
            let countMatches = list.count == folder.issueCount
            if countMatches {
                reporter.report("GET /v1/folders/{id}/issues", .ok("\(list.count) issues"))
            } else {
                reporter.report(
                    "GET /v1/folders/{id}/issues",
                    .fail("count \(list.count) doesn't match FolderInfo.issueCount \(folder.issueCount)")
                )
            }
        } else {
            reporter.report("GET /v1/folders/{id}/issues", .fail("status=\(result.status)"))
            return
        }
    } catch {
        reporter.report("GET /v1/folders/{id}/issues", .fail("\(error)"))
        return
    }

    if metas.isEmpty {
        reporter.report("GET /v1/folders/{id}/issues/{iid}", .skip("no issues to test"))
        _ = reporter.summary()
        return
    }

    let issue: IssueMetadata
    if let requested = opts.issue, let match = metas.first(where: { $0.id == requested }) {
        issue = match
    } else {
        issue = metas[0]
    }

    // 7. /v1/folders/<id>/issues/<iid>.
    var detail: IssueDetail?
    do {
        let result = try await get(
            base.appendingPathComponent("v1/folders/\(folder.id)/issues/\(issue.id)"),
            token: token,
            session: session
        )
        if result.status == 200,
           let payload = try? RemoteProtocol.decoder.decode(IssueDetail.self, from: result.body) {
            detail = payload
            if !payload.body.isEmpty {
                reporter.report(
                    "GET /v1/folders/{id}/issues/\(issue.id)",
                    .ok("body=\(payload.body.count)B attachments=\(payload.attachments.count)")
                )
            } else {
                reporter.report("GET /v1/folders/{id}/issues/\(issue.id)", .fail("body is empty"))
            }
        } else {
            reporter.report("GET /v1/folders/{id}/issues/\(issue.id)", .fail("status=\(result.status)"))
        }
    } catch {
        reporter.report("GET /v1/folders/{id}/issues/\(issue.id)", .fail("\(error)"))
    }

    // 8. Attachment streaming, if any.
    if let detail = detail, let attachment = detail.attachments.first {
        do {
            let result = try await get(
                base.appendingPathComponent("v1/folders/\(folder.id)/issues/\(issue.id)/attachments/\(attachment)"),
                token: token,
                session: session
            )
            let lengthHeader = (result.headers["Content-Length"] as? String).flatMap(Int.init)
            if result.status == 200, lengthHeader == result.body.count {
                let hash = sha256Prefix(result.body)
                reporter.report(
                    "GET /v1/.../attachments/\(attachment)",
                    .ok("\(result.body.count)B sha256=\(hash)…")
                )
            } else {
                reporter.report(
                    "GET /v1/.../attachments/\(attachment)",
                    .fail("status=\(result.status), Content-Length=\(lengthHeader ?? -1), body=\(result.body.count)")
                )
            }
        } catch {
            reporter.report("GET /v1/.../attachments/\(attachment)", .fail("\(error)"))
        }
    } else {
        reporter.report("attachment streaming", .skip("issue has no attachments"))
    }

    // 9. WebSocket /v1/events — not yet implemented (#0100).
    reporter.report("WebSocket /v1/events", .skip("ws not yet implemented (#0100)"))
}

// MARK: - Helpers

func prefix(_ data: Data, max: Int = 200) -> String {
    let s = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    if s.count > max { return s.prefix(max) + "…" }
    return s
}

func errorReason(in body: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
    return json["error"] as? String
}

import CryptoKit

func sha256Prefix(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Main

@MainActor
func main() async {
    var opts = parseArgs(CommandLine.arguments)
    reporter.verbose = opts.verbose

    // Token can come from the environment so it stays out of shell history.
    if opts.token == nil, let env = ProcessInfo.processInfo.environment["ISSUES_REMOTE_TOKEN"], !env.isEmpty {
        opts.token = env
    }

    if opts.host == nil {
        printUsage()
        exit(2)
    }

    await runChecks(opts: opts)
    exit(Int32(reporter.summary()))
}

await main()
