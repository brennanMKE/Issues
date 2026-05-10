import Foundation
import IssuesRemoteProtocol

// MARK: - Argument parsing

struct Options {
    var host: String?
    var token: String?
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
    return opts
}

func printUsage() {
    let usage = """
    Usage: issues-remote-smoke --host HOST:PORT [--token iat_...] [--folder ID] [--issue ID] [-v]

    Hits every v1 endpoint on a running Issues.app host and reports pass/fail.

    Options:
      --host  HOST:PORT  required. e.g. 100.74.12.5:51823 or my-mac.local:51823
      --token iat_...    bearer token. Falls back to $ISSUES_REMOTE_TOKEN.
      --folder ID        optional. Defaults to the first folder /v1/folders returns.
      --issue  ID        optional. Defaults to the first issue.
      --verbose, -v      print full response bodies.
      --help, -h         this message.

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

    var description: String {
        switch self {
        case .transport(let m): return m
        case .noResponse: return "no response"
        }
    }
}

func get(_ url: URL, token: String?, session: URLSession = .shared) async throws -> HTTPResult {
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
        throw HTTPError.transport("\(err.localizedDescription) [\(err.code.rawValue)]")
    }
}

// MARK: - Checks

func baseURL(for host: String) -> URL? {
    URL(string: "http://\(host)")
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

    // 1. /v1/host with valid token.
    var hostInfo: HostInfo?
    do {
        let result = try await get(base.appendingPathComponent("v1/host"), token: token)
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
        let result = try await get(base.appendingPathComponent("v1/host"), token: nil)
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
        let result = try await get(base.appendingPathComponent("v1/host"), token: "iat_garbage")
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
        let result = try await get(base.appendingPathComponent("v1/folders"), token: token)
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
        let result = try await get(base.appendingPathComponent("v1/folders/\(folder.id)"), token: token)
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
        let result = try await get(base.appendingPathComponent("v1/folders/\(folder.id)/issues"), token: token)
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
            token: token
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
                token: token
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
