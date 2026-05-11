import Foundation

/// Minimal viewer-side HTTP client for the host (#0094). The picker flow
/// (#0091 / #0096 / #0097) only needs the two unary endpoints:
///   - `GET /v1/host`     — connectivity + token validation
///   - `GET /v1/folders`  — list of folders the host is serving
///
/// All requests use HTTP (plaintext) for v1 — the host listens on a local
/// network and the bearer token is the auth boundary. TLS / DoH is tracked
/// elsewhere in the RemoteAccess plan.
///
/// `host` is taken verbatim (DNS name, IPv4, IPv6, Tailscale name) and pasted
/// into the URL; IPv6 literals are bracketed automatically.
protocol RemoteClientProtocol: AnyObject, Sendable {
    /// Calls `GET /v1/host`. Pass `token = nil` to probe connectivity (the
    /// host will return 401 if reachable but unauthenticated, which the
    /// picker's "manual host" step uses as a "valid host" signal).
    func fetchHost(host: String, port: UInt16, token: String?) async throws -> HostInfo

    /// Calls `GET /v1/folders` with a bearer token. Requires a token —
    /// folders are never anonymous.
    func fetchFolders(host: String, port: UInt16, token: String) async throws -> [FolderInfo]
}

/// Errors thrown by `URLSessionRemoteClient`. The picker view maps these to
/// inline error messages; `unauthorized` is the one branching case the flow
/// uses to advance from host-pick to token-paste.
enum RemoteClientError: Error, Equatable, Sendable {
    /// The host returned `401 Unauthorized`. From the picker's point of view:
    /// "we reached the host, but the request had no/invalid token". The
    /// "validate host" step in #0091 treats this as success-with-token-needed.
    case unauthorized
    /// Any non-2xx, non-401 HTTP status. Carries the status code so callers
    /// can surface "host returned 503" if useful.
    case httpStatus(Int)
    /// `URLError` from the system networking stack — timeouts, refusals,
    /// DNS failures all live here.
    case transport(String)
    /// JSON decode failed against the wire schema. Indicates a host/viewer
    /// version mismatch.
    case decoding(String)
    /// The host string couldn't be turned into a valid URL.
    case invalidURL
}

/// Concrete `URLSession`-backed client. `Sendable` so it can be passed
/// across actor boundaries; internal state is just the configured session.
final class URLSessionRemoteClient: RemoteClientProtocol, @unchecked Sendable {

    private let session: URLSession
    /// Per-request connect timeout in seconds (#0091 spec: 3 s).
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 3.0) {
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        // The viewer talks to local-network hosts; let the system handle
        // caching policy — we want fresh data on every fetch.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func fetchHost(host: String, port: UInt16, token: String?) async throws -> HostInfo {
        let request = try makeRequest(host: host, port: port, path: "/v1/host", token: token)
        let data = try await performJSON(request)
        do {
            return try RemoteProtocol.decoder.decode(HostInfo.self, from: data)
        } catch {
            throw RemoteClientError.decoding(error.localizedDescription)
        }
    }

    func fetchFolders(host: String, port: UInt16, token: String) async throws -> [FolderInfo] {
        let request = try makeRequest(host: host, port: port, path: "/v1/folders", token: token)
        let data = try await performJSON(request)
        do {
            return try RemoteProtocol.decoder.decode([FolderInfo].self, from: data)
        } catch {
            throw RemoteClientError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func makeRequest(host: String, port: UInt16, path: String, token: String?) throws -> URLRequest {
        guard let url = Self.url(host: host, port: port, path: path) else {
            throw RemoteClientError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func performJSON(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw RemoteClientError.transport(urlError.localizedDescription)
        } catch {
            throw RemoteClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteClientError.transport("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw RemoteClientError.unauthorized
        default:
            throw RemoteClientError.httpStatus(http.statusCode)
        }
    }

    /// Builds the request URL. IPv6 literals are bracketed automatically so
    /// `URL(string:)` parses them correctly; everything else is pasted in
    /// verbatim. Returns `nil` on a malformed host.
    static func url(host: String, port: UInt16, path: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let bracketed: String
        if trimmed.contains(":") && !trimmed.hasPrefix("[") {
            bracketed = "[\(trimmed)]"
        } else {
            bracketed = trimmed
        }
        return URL(string: "http://\(bracketed):\(port)\(path)")
    }
}
