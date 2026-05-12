import Foundation
import os.log

#if os(macOS) || os(iOS)

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "RemoteClient")

/// Network-layer client used by `RemoteHostIssueSource` (#0094). Wraps
/// `URLSession` with the v1 REST shape from #0080 / #0081 and the
/// `Authorization: Bearer …` header. Cross-platform (`#if os(macOS) ||
/// os(iOS)`) so the iOS viewer in #0108 can reuse it.
///
/// The protocol exists for testability — the source takes a
/// `RemoteClientProtocol`, production wires a `URLSessionRemoteClient`,
/// tests can substitute a stub. The protocol surface is intentionally
/// minimal: every method maps 1:1 to a documented endpoint.
protocol RemoteClientProtocol: Sendable {
    func fetchFolder(id: String) async throws -> FolderInfo
    /// Lists every folder the host is currently serving. Used by #0103's
    /// find-by-name fallback when a stale `folderId` returns 404.
    func fetchFolders() async throws -> [FolderInfo]
    func fetchIssues(folderId: String) async throws -> [IssueMetadata]
    func fetchIssueDetail(folderId: String, id: String) async throws -> IssueDetail

    /// Streams the bytes of an attachment via `URLSession.bytes(for:)`.
    /// Returns the raw bytes; callers decide whether to decode (`NSImage`,
    /// movie, etc.). Throws `RemoteClientError.notFound` for a missing
    /// attachment, `.unauthorized` for an expired token, etc.
    func fetchAttachmentData(folderId: String, issueId: String, name: String) async throws -> Data
}

/// Errors surfaced by `RemoteClientProtocol` implementations. Maps onto
/// the wire-shape semantics from #0079 / #0080:
///
/// - `.unauthorized` — server returned 401 (missing / invalid / expired
///   token). Source surfaces `.tokenInvalid` upstream.
/// - `.folderNotFound` — 404 on a folder-scoped path. Source surfaces
///   `.folderUnavailable` upstream so the viewer can fall back to
///   find-by-name (#0098).
/// - `.notFound` — 404 on a non-folder path (rare; e.g. unknown issue id).
/// - `.transport(message)` — `URLError` or generic networking failure.
/// - `.decode(message)` — JSON decode failure.
/// - `.unexpectedStatus(code)` — anything else (5xx, 413, …).
enum RemoteClientError: Error, Equatable {
    case unauthorized
    case folderNotFound
    case notFound
    case transport(String)
    case decode(String)
    case unexpectedStatus(Int)
}

struct URLSessionRemoteClient: RemoteClientProtocol {

    let host: String
    let port: UInt16
    let token: String
    let session: URLSession

    init(host: String, port: UInt16, token: String, session: URLSession = .shared) {
        self.host = host
        self.port = port
        self.token = token
        self.session = session
    }

    // MARK: - Endpoints

    func fetchFolder(id: String) async throws -> FolderInfo {
        let url = try makeURL("/v1/folders/\(id)")
        return try await get(url, kind: .folder)
    }

    func fetchFolders() async throws -> [FolderInfo] {
        let url = try makeURL("/v1/folders")
        return try await get(url, kind: .folder)
    }

    func fetchIssues(folderId: String) async throws -> [IssueMetadata] {
        let url = try makeURL("/v1/folders/\(folderId)/issues")
        return try await get(url, kind: .folder)
    }

    func fetchIssueDetail(folderId: String, id: String) async throws -> IssueDetail {
        let url = try makeURL("/v1/folders/\(folderId)/issues/\(id)")
        return try await get(url, kind: .issue)
    }

    func fetchAttachmentData(folderId: String, issueId: String, name: String) async throws -> Data {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = try makeURL("/v1/folders/\(folderId)/issues/\(issueId)/attachments/\(encoded)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RemoteClientError.transport("no HTTPURLResponse")
            }
            switch http.statusCode {
            case 200:
                var data = Data()
                if let expected = Int(http.value(forHTTPHeaderField: "Content-Length") ?? "") {
                    data.reserveCapacity(expected)
                }
                for try await byte in asyncBytes {
                    data.append(byte)
                }
                return data
            case 401: throw RemoteClientError.unauthorized
            case 404: throw RemoteClientError.notFound
            default:  throw RemoteClientError.unexpectedStatus(http.statusCode)
            }
        } catch let error as RemoteClientError {
            throw error
        } catch {
            throw RemoteClientError.transport(error.localizedDescription)
        }
    }

    // MARK: - Plumbing

    /// Distinguishes "folder-scoped 404" from "issue-scoped 404" so
    /// callers can react differently (folder → fall back to find-by-name;
    /// issue → "this row vanished").
    private enum PathKind {
        case folder
        case issue
    }

    private func get<T: Decodable>(_ url: URL, kind: PathKind) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            logger.warning("transport failure url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw RemoteClientError.transport(error.localizedDescription)
        } catch {
            throw RemoteClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteClientError.transport("no HTTPURLResponse")
        }
        switch http.statusCode {
        case 200:
            do {
                return try RemoteProtocol.decoder.decode(T.self, from: data)
            } catch {
                throw RemoteClientError.decode(error.localizedDescription)
            }
        case 401:
            throw RemoteClientError.unauthorized
        case 404:
            switch kind {
            case .folder: throw RemoteClientError.folderNotFound
            case .issue: throw RemoteClientError.notFound
            }
        default:
            throw RemoteClientError.unexpectedStatus(http.statusCode)
        }
    }

    private func makeURL(_ path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = path
        guard let url = components.url else {
            throw RemoteClientError.transport("malformed url for \(path)")
        }
        return url
    }
}

#endif
