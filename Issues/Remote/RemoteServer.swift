import Foundation
import os.log

#if os(macOS)
import Network
#endif

/// Forward-declared shape for the multi-folder host store. Grown alongside
/// #0080's REST handlers; #0085 (per-folder hosting toggles) is the
/// concrete implementation that filters open tabs by the user's hosting
/// preferences.
protocol MultiFolderStore: AnyObject {
    /// User-visible host label, e.g. "Brennan's MacBook Air". Surfaced in
    /// `/v1/host`. The concrete host reads from system APIs; tests stub
    /// directly.
    var hostDisplayName: String { get }

    /// Snapshot of folders currently being served. Each call returns fresh
    /// values so the wire response reflects the latest in-memory state.
    func currentlyHostedFolders() -> [HostedFolder]

    /// Lookup by `folderId` (#0082). Returns nil for unknown ids; the
    /// handlers map that to `404 not_found`.
    func currentlyHostedFolder(forId id: String) -> HostedFolder?
}

extension MultiFolderStore {
    /// Compatibility shim for callers that only need the id list (#0079
    /// placeholder routes). Defaults to deriving from
    /// `currentlyHostedFolders()`.
    var hostedFolderIds: [String] {
        currentlyHostedFolders().map { $0.id }
    }
}

/// Adapter the server uses to read a single served folder. The concrete
/// host populates these from its `IssueStore` instances; tests can build
/// them directly without touching disk.
struct HostedFolder: Equatable {
    let id: String
    let folderURL: URL
    let displayName: String
    let projectMetadata: ProjectMetadata?
    let issues: [Issue]
    let modifiedAt: Date
}

/// Information about a peer that has connected to the host. Surfaced in
/// the connected-viewers list (#0092). For #0079 we capture just the
/// remote address; the token name (and thus `displayName`) is wired in
/// once the auth middleware passes it through.
struct PeerInfo: Equatable, Sendable {
    var remoteAddress: String
    var tokenName: String?
    var connectedAt: Date
}

// MARK: - HTTP types

/// Parsed inbound HTTP request. Only `GET` is supported in v1; the parser
/// rejects everything else with `400 bad_request`.
struct HTTPRequest: Equatable {
    var method: String
    /// Absolute path component of the request line, with `?query` stripped.
    var path: String
    var headers: [String: String]

    /// Convenience for the auth middleware.
    var authorizationHeader: String? {
        // HTTP header field names are case-insensitive (RFC 7230 §3.2).
        for (key, value) in headers where key.caseInsensitiveCompare("Authorization") == .orderedSame {
            return value
        }
        return nil
    }
}

/// Outbound HTTP response. For JSON responses `body` is sent as-is and
/// `Content-Length` is computed from `body.count`. For attachment streaming
/// (#0081), `streamingFile` and `contentLength` together tell the server to
/// send headers then stream the file in chunks; `body` is unused.
struct HTTPResponse: Equatable {
    var status: Int
    var statusText: String
    var headers: [String: String]
    var body: Data
    /// When non-nil, the server streams the file at this URL after the
    /// header block. `contentLength` must be set so the wire `Content-Length`
    /// is correct without reading the file twice.
    var streamingFile: URL?
    /// Required when `streamingFile` is set; ignored otherwise.
    var contentLength: Int?

    init(
        status: Int,
        statusText: String,
        headers: [String: String],
        body: Data = Data(),
        streamingFile: URL? = nil,
        contentLength: Int? = nil
    ) {
        self.status = status
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.streamingFile = streamingFile
        self.contentLength = contentLength
    }

    /// Serialize to wire bytes (HTTP/1.1, `Connection: close`). For
    /// streaming responses this returns the headers only — the server
    /// streams the body separately.
    func serialized() -> Data {
        var out = "HTTP/1.1 \(status) \(statusText)\r\n"
        var allHeaders = headers
        let length = streamingFile != nil ? (contentLength ?? 0) : body.count
        allHeaders["Content-Length"] = "\(length)"
        allHeaders["Connection"] = "close"
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            out += "\(key): \(value)\r\n"
        }
        out += "\r\n"
        var data = Data(out.utf8)
        if streamingFile == nil {
            data.append(body)
        }
        return data
    }

    static func json(_ status: Int, statusText: String, payload: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(
            status: status,
            statusText: statusText,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    static func ok(payload: [String: Any]) -> HTTPResponse {
        json(200, statusText: "OK", payload: payload)
    }

    static func badRequest(reason: String) -> HTTPResponse {
        json(400, statusText: "Bad Request", payload: ["error": reason])
    }

    static func unauthorized(reason: String) -> HTTPResponse {
        json(401, statusText: "Unauthorized", payload: ["error": reason])
    }

    static func notFound() -> HTTPResponse {
        json(404, statusText: "Not Found", payload: ["error": "not_found"])
    }

    static func internalError(debugMessage: String?) -> HTTPResponse {
        var payload: [String: Any] = ["error": "internal_error"]
        #if DEBUG
        if let message = debugMessage {
            payload["debug"] = message
        }
        #endif
        return json(500, statusText: "Internal Server Error", payload: payload)
    }

    /// Streaming response for attachment downloads (#0081). The body is
    /// sent in chunks from `fileURL`; callers must already have validated
    /// `contentLength` via a stat / `attributesOfItem`.
    static func file(
        url: URL,
        contentType: String,
        contentLength: Int,
        lastModified: Date
    ) -> HTTPResponse {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        // RFC 7231 IMF-fixdate.
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return HTTPResponse(
            status: 200,
            statusText: "OK",
            headers: [
                "Content-Type": contentType,
                "Last-Modified": formatter.string(from: lastModified)
            ],
            body: Data(),
            streamingFile: url,
            contentLength: contentLength
        )
    }
}

/// Hand-rolled HTTP/1.1 request parser. Strict on purpose — anything
/// unexpected returns a `.badRequest` rather than trying to be liberal.
/// Only `GET` is accepted in v1; bodies on `GET` are rejected.
enum HTTPRequestParser {

    /// Maximum size of the request line + headers we'll read. Bodies on
    /// `GET` are forbidden, so we never need to read past the header
    /// terminator anyway.
    static let maxHeaderBytes = 16 * 1024

    enum ParseError: Error, Equatable {
        case malformedRequestLine
        case unsupportedMethod
        case bodyOnGet
        case missingHost
        case headersTooLarge
    }

    /// Parses the bytes up through (and including) the `\r\n\r\n`
    /// terminator. Returns the parsed request plus the byte count
    /// consumed; any bytes past the terminator are an error on `GET`.
    static func parse(_ data: Data) throws -> HTTPRequest {
        guard data.count <= maxHeaderBytes else {
            throw ParseError.headersTooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError.malformedRequestLine
        }
        // Split on CRLF; the last meaningful line is followed by an
        // empty line indicating end-of-headers. We accept LF-only as a
        // tolerance for hand-typed test inputs.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            throw ParseError.malformedRequestLine
        }
        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count == 3 else {
            throw ParseError.malformedRequestLine
        }
        let method = parts[0]
        let target = parts[1]
        let version = parts[2]
        guard version.hasPrefix("HTTP/1.") else {
            throw ParseError.malformedRequestLine
        }
        guard method == "GET" else {
            throw ParseError.unsupportedMethod
        }
        // Strip query and fragment.
        let path: String = {
            if let q = target.firstIndex(of: "?") {
                return String(target[..<q])
            }
            return target
        }()

        var headers: [String: String] = [:]
        var sawTerminator = false
        var bodyBytes = 0
        for line in lines.dropFirst() {
            if line.isEmpty {
                sawTerminator = true
                continue
            }
            if sawTerminator {
                bodyBytes += line.utf8.count
                continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                throw ParseError.malformedRequestLine
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        if bodyBytes > 0 {
            throw ParseError.bodyOnGet
        }
        guard headers.contains(where: { $0.key.caseInsensitiveCompare("Host") == .orderedSame }) else {
            throw ParseError.missingHost
        }

        return HTTPRequest(method: method, path: path, headers: headers)
    }
}

// MARK: - Route table

/// One row in the route table. Pattern segments that begin with `{` and
/// end with `}` are placeholders; everything else is a literal match.
/// `/v1/folders/{folderId}/issues/{id}` matches `/v1/folders/abc/issues/0001`
/// and yields `["folderId": "abc", "id": "0001"]`.
struct Route {
    var method: String
    var pathPattern: String
    /// Captures `{...}` placeholders into the dictionary handed to the
    /// handler. Returns the response. Throws fall through to a 500.
    var handler: (HTTPRequest, [String: String]) throws -> HTTPResponse
}

struct RouteTable {
    var routes: [Route] = []

    /// Returns the matching route plus captured placeholders, or nil if
    /// no route matches. Method is matched case-insensitively for safety.
    func match(method: String, path: String) -> (Route, [String: String])? {
        let pathSegments = Self.segments(of: path)
        for route in routes where route.method.caseInsensitiveCompare(method) == .orderedSame {
            let patternSegments = Self.segments(of: route.pathPattern)
            guard patternSegments.count == pathSegments.count else { continue }
            var captures: [String: String] = [:]
            var matched = true
            for (pat, seg) in zip(patternSegments, pathSegments) {
                if pat.hasPrefix("{") && pat.hasSuffix("}") {
                    let name = String(pat.dropFirst().dropLast())
                    captures[name] = seg
                } else if pat != seg {
                    matched = false
                    break
                }
            }
            if matched { return (route, captures) }
        }
        return nil
    }

    private static func segments(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}

// MARK: - Auth middleware

enum AuthOutcome: Equatable {
    case ok(record: TokenRecord)
    case missingHeader
    case malformedHeader
    case invalidToken
    case expiredToken
}

enum AuthMiddleware {

    /// Pulls a bearer token out of the `Authorization` header value.
    /// Returns nil if the header is missing or doesn't start with the
    /// `Bearer ` scheme.
    static func extractBearer(_ header: String?) -> String? {
        guard let header = header else { return nil }
        // Case-insensitive scheme per RFC 6750 §2.1.
        let lower = header.lowercased()
        guard lower.hasPrefix("bearer ") else { return nil }
        let token = header.dropFirst("bearer ".count).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    #if os(macOS)
    /// Validates the `Authorization` header using `AccessToken`. Pure
    /// classification — does not call `touch`; the server's request
    /// loop schedules that asynchronously after the response is sent.
    static func authenticate(
        authorizationHeader: String?,
        service: String = AccessToken.defaultService
    ) -> AuthOutcome {
        guard let header = authorizationHeader else { return .missingHeader }
        guard let token = extractBearer(header) else { return .malformedHeader }
        do {
            let record = try AccessToken.validate(plaintext: token, from: nil, service: service)
            return .ok(record: record)
        } catch AccessTokenError.notFound {
            return .invalidToken
        } catch AccessTokenError.expired {
            return .expiredToken
        } catch {
            return .invalidToken
        }
    }

    /// Maps an `AuthOutcome` to a `401` response (or returns nil on
    /// success). Convenience for the request pipeline.
    static func failureResponse(for outcome: AuthOutcome) -> HTTPResponse? {
        switch outcome {
        case .ok: return nil
        case .missingHeader: return .unauthorized(reason: "missing_token")
        case .malformedHeader: return .unauthorized(reason: "missing_token")
        case .invalidToken: return .unauthorized(reason: "invalid_token")
        case .expiredToken: return .unauthorized(reason: "expired_token")
        }
    }
    #endif
}

#if os(macOS)

// MARK: - Listener

private nonisolated let logger = Logger(subsystem: Logging.subsystem, category: "RemoteServer")

@MainActor
@Observable
final class RemoteServer {

    private let store: MultiFolderStore
    private var routes: RouteTable
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Peers currently holding a connection, keyed by `ObjectIdentifier`
    /// of the `NWConnection`. Mirrored to the observable `connectedPeers`
    /// array so SwiftUI views (#0092) re-render when the set changes.
    private var peerInfo: [ObjectIdentifier: PeerInfo] = [:]
    private(set) var connectedPeers: [PeerInfo] = []
    private(set) var listeningPort: UInt16?

    /// Persistence key for the chosen port — `0` means "let the OS pick".
    private static let portDefaultsKey = "RemoteServer.port"

    init(store: MultiFolderStore) {
        self.store = store
        self.routes = RouteTable()
        installDefaultRoutes()
    }

    // MARK: Routes

    /// Wires up the v1 REST endpoints (#0080). Each handler returns a
    /// fully-formed `HTTPResponse`; failures map to `404 not_found` or
    /// `500 internal_error` per the issue's error table.
    private func installDefaultRoutes() {
        routes.routes.append(contentsOf: RemoteHandlers.routes(store: store))
    }

    // MARK: Lifecycle

    func start() throws {
        guard listener == nil else { return }

        let savedPort = UInt16(UserDefaults.standard.integer(forKey: Self.portDefaultsKey))
        let port = NWEndpoint.Port(rawValue: savedPort) ?? .any

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Listen on all interfaces — auth + the user's network shape is
        // what makes this safe. Interface pinning is deferred to v2.
        parameters.requiredInterfaceType = .other // ignored; placeholder

        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in self.handleListenerState(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor in self.accept(connection: connection) }
        }
        listener.start(queue: .global(qos: .userInitiated))
        logger.notice("RemoteServer.start requested port=\(savedPort, privacy: .public)")
    }

    func stop() {
        logger.notice("RemoteServer.stop")
        listener?.cancel()
        listener = nil
        listeningPort = nil
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        peerInfo.removeAll()
        connectedPeers.removeAll()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                listeningPort = port
                UserDefaults.standard.set(Int(port), forKey: Self.portDefaultsKey)
                logger.notice("RemoteServer ready port=\(port, privacy: .public)")
            }
        case .failed(let error):
            logger.error("RemoteServer failed: \(error.localizedDescription, privacy: .public)")
            stop()
        case .cancelled:
            listeningPort = nil
        default:
            break
        }
    }

    // MARK: Connection handling

    private func accept(connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        let remote = Self.describe(endpoint: connection.endpoint)
        let peer = PeerInfo(remoteAddress: remote, tokenName: nil, connectedAt: Date())
        peerInfo[key] = peer
        connectedPeers = Array(peerInfo.values)
        logger.debug("accept peer=\(remote, privacy: .public)")

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .cancelled = state {
                Task { @MainActor in self.dropConnection(key: key) }
            } else if case .failed = state {
                Task { @MainActor in self.dropConnection(key: key) }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))

        Task { @MainActor in
            await self.handleRequest(on: connection, key: key, remote: remote)
            self.dropConnection(key: key)
        }
    }

    private func dropConnection(key: ObjectIdentifier) {
        if let conn = connections.removeValue(forKey: key) {
            conn.cancel()
        }
        peerInfo.removeValue(forKey: key)
        connectedPeers = Array(peerInfo.values)
    }

    private func handleRequest(on connection: NWConnection, key: ObjectIdentifier, remote: String) async {
        let buffer = await readHeaders(on: connection)
        guard let buffer else {
            await send(.badRequest(reason: "read_failed"), on: connection)
            return
        }
        let request: HTTPRequest
        do {
            request = try HTTPRequestParser.parse(buffer)
        } catch let error as HTTPRequestParser.ParseError {
            await send(.badRequest(reason: "\(error)"), on: connection)
            return
        } catch {
            await send(.badRequest(reason: "parse_error"), on: connection)
            return
        }

        let outcome = AuthMiddleware.authenticate(authorizationHeader: request.authorizationHeader)
        if let failure = AuthMiddleware.failureResponse(for: outcome) {
            await send(failure, on: connection)
            return
        }
        // Thread the token's user-chosen name into the peer record so
        // the connected-viewers list (#0092) shows it.
        if case .ok(let record) = outcome, var info = peerInfo[key] {
            info.tokenName = record.name
            peerInfo[key] = info
            connectedPeers = Array(peerInfo.values)
        }

        guard let (route, captures) = routes.match(method: request.method, path: request.path) else {
            await send(.notFound(), on: connection)
            return
        }
        do {
            let response = try route.handler(request, captures)
            await send(response, on: connection)

            // Touch the token off the response path so the read isn't
            // blocked on a Keychain write.
            if case .ok(let record) = outcome {
                Task.detached {
                    do {
                        try AccessToken.touch(hash: record.hash, from: remote)
                    } catch {
                        logger.warning("token touch failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            await send(.internalError(debugMessage: error.localizedDescription), on: connection)
        }
    }

    /// Reads bytes from `connection` until `\r\n\r\n` is seen or
    /// `maxHeaderBytes` is exceeded. v1 supports `GET` only, so there's
    /// never a body to chase past the header terminator.
    private func readHeaders(on connection: NWConnection) async -> Data? {
        var accumulated = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while accumulated.count <= HTTPRequestParser.maxHeaderBytes {
            let chunk: Data? = await withCheckedContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if let error {
                        logger.warning("receive failed: \(error.localizedDescription, privacy: .public)")
                        cont.resume(returning: nil)
                        return
                    }
                    if let data = data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else if isComplete {
                        cont.resume(returning: nil)
                    } else {
                        cont.resume(returning: Data())
                    }
                }
            }
            guard let chunk else { return nil }
            if chunk.isEmpty { continue }
            accumulated.append(chunk)
            if accumulated.range(of: terminator) != nil {
                return accumulated
            }
        }
        return nil
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) async {
        // Headers (the call honors `streamingFile` to write headers only).
        let header = response.serialized()
        await sendBytes(header, on: connection)
        // Stream the file body in chunks if requested. Errors abort the
        // stream — the connection will close, the viewer's URLSession
        // surfaces the truncation.
        if let fileURL = response.streamingFile {
            await streamFile(at: fileURL, on: connection)
        }
    }

    private func sendBytes(_ bytes: Data, on connection: NWConnection) async {
        await withCheckedContinuation { cont in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error {
                    logger.warning("send failed: \(error.localizedDescription, privacy: .public)")
                }
                cont.resume()
            })
        }
    }

    private static let streamChunkSize = 64 * 1024

    private func streamFile(at fileURL: URL, on connection: NWConnection) async {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            logger.warning("attachment stream open failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        defer { try? handle.close() }
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: Self.streamChunkSize) ?? Data()
            } catch {
                logger.warning("attachment stream read failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            if chunk.isEmpty { return }
            await sendBytes(chunk, on: connection)
        }
    }

    // MARK: Helpers

    private static func describe(endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port.rawValue)"
        default:
            return "\(endpoint)"
        }
    }
}

#endif
