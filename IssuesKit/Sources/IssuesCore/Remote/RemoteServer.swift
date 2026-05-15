import Foundation
import os.log

#if os(macOS)
import Network
#endif

/// Forward-declared shape for the multi-folder host store. Grown alongside
/// #0080's REST handlers; #0085 (per-folder hosting toggles) is the
/// concrete implementation that filters open tabs by the user's hosting
/// preferences.
public protocol MultiFolderStore: AnyObject {
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

public extension MultiFolderStore {
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
public struct HostedFolder: Equatable {
    public let id: String
    public let folderURL: URL
    public let displayName: String
    public let projectMetadata: ProjectMetadata?
    public let issues: [Issue]
    public let modifiedAt: Date

    public init(
        id: String,
        folderURL: URL,
        displayName: String,
        projectMetadata: ProjectMetadata?,
        issues: [Issue],
        modifiedAt: Date
    ) {
        self.id = id
        self.folderURL = folderURL
        self.displayName = displayName
        self.projectMetadata = projectMetadata
        self.issues = issues
        self.modifiedAt = modifiedAt
    }
}

/// Information about a peer that has connected to the host. Surfaced in
/// the connected-viewers list (#0092). For #0079 we capture just the
/// remote address; the token name (and thus `displayName`) is wired in
/// once the auth middleware passes it through.
public struct PeerInfo: Equatable, Sendable {
    public var remoteAddress: String
    public var tokenName: String?
    public var connectedAt: Date

    public init(remoteAddress: String, tokenName: String?, connectedAt: Date) {
        self.remoteAddress = remoteAddress
        self.tokenName = tokenName
        self.connectedAt = connectedAt
    }
}

// MARK: - HTTP types

/// Parsed inbound HTTP request. Only `GET` is supported in v1; the parser
/// rejects everything else with `400 bad_request`.
public struct HTTPRequest: Equatable {
    public var method: String
    /// Absolute path component of the request line, with `?query` stripped.
    public var path: String
    public var headers: [String: String]

    /// Convenience for the auth middleware.
    public var authorizationHeader: String? {
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
public struct HTTPResponse: Equatable {
    public var status: Int
    public var statusText: String
    public var headers: [String: String]
    public var body: Data
    /// When non-nil, the server streams the file at this URL after the
    /// header block. `contentLength` must be set so the wire `Content-Length`
    /// is correct without reading the file twice.
    public var streamingFile: URL?
    /// Required when `streamingFile` is set; ignored otherwise.
    public var contentLength: Int?

    public init(
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
    public func serialized() -> Data {
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

    public static func json(_ status: Int, statusText: String, payload: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(
            status: status,
            statusText: statusText,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    public static func ok(payload: [String: Any]) -> HTTPResponse {
        json(200, statusText: "OK", payload: payload)
    }

    public static func badRequest(reason: String) -> HTTPResponse {
        json(400, statusText: "Bad Request", payload: ["error": reason])
    }

    public static func unauthorized(reason: String) -> HTTPResponse {
        json(401, statusText: "Unauthorized", payload: ["error": reason])
    }

    public static func notFound() -> HTTPResponse {
        json(404, statusText: "Not Found", payload: ["error": "not_found"])
    }

    public static func internalError(debugMessage: String?) -> HTTPResponse {
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
    public static func file(
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
public enum HTTPRequestParser {

    /// Maximum size of the request line + headers we'll read. Bodies on
    /// `GET` are forbidden, so we never need to read past the header
    /// terminator anyway.
    public static let maxHeaderBytes = 16 * 1024

    public enum ParseError: Error, Equatable {
        case malformedRequestLine
        case unsupportedMethod
        case bodyOnGet
        case missingHost
        case headersTooLarge
    }

    /// Parses the bytes up through (and including) the `\r\n\r\n`
    /// terminator. Returns the parsed request plus the byte count
    /// consumed; any bytes past the terminator are an error on `GET`.
    public static func parse(_ data: Data) throws -> HTTPRequest {
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
public struct Route {
    public var method: String
    public var pathPattern: String
    /// Captures `{...}` placeholders into the dictionary handed to the
    /// handler. Returns the response. Throws fall through to a 500.
    public var handler: (HTTPRequest, [String: String]) throws -> HTTPResponse

    public init(method: String, pathPattern: String, handler: @escaping (HTTPRequest, [String: String]) throws -> HTTPResponse) {
        self.method = method
        self.pathPattern = pathPattern
        self.handler = handler
    }
}

public struct RouteTable {
    public var routes: [Route] = []

    public init(routes: [Route] = []) {
        self.routes = routes
    }

    /// Returns the matching route plus captured placeholders, or nil if
    /// no route matches. Method is matched case-insensitively for safety.
    public func match(method: String, path: String) -> (Route, [String: String])? {
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

public enum AuthOutcome: Equatable {
    case ok(record: TokenRecord)
    case missingHeader
    case malformedHeader
    case invalidToken
    case expiredToken
}

public enum AuthMiddleware {

    /// Pulls a bearer token out of the `Authorization` header value.
    /// Returns nil if the header is missing or doesn't start with the
    /// `Bearer ` scheme.
    public static func extractBearer(_ header: String?) -> String? {
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
    public static func authenticate(
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
    public static func failureResponse(for outcome: AuthOutcome) -> HTTPResponse? {
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
public final class RemoteServer {

    private let store: MultiFolderStore
    /// TLS identity (#0112). When non-nil, `start()` configures the listener
    /// with `NWProtocolTLS.Options` bound to this identity. When nil,
    /// `start()` throws — v2 is TLS or nothing.
    private let identity: RemoteServerIdentity?
    private var routes: RouteTable
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Peers currently holding a connection, keyed by `ObjectIdentifier`
    /// of the `NWConnection`. Mirrored to the observable `connectedPeers`
    /// array so SwiftUI views (#0092) re-render when the set changes.
    private var peerInfo: [ObjectIdentifier: PeerInfo] = [:]
    public private(set) var connectedPeers: [PeerInfo] = []
    public private(set) var listeningPort: UInt16?

    // MARK: WebSocket state (#0100, #0101)

    /// Open WebSocket sessions keyed by their `ObjectIdentifier`. The set
    /// is the source of truth for "this connection is now in WS mode"; the
    /// underlying `NWConnection` lifetime is owned by the session, so we
    /// don't keep it in `connections` while WS is active.
    private var sessions: [ObjectIdentifier: WebSocketSession] = [:]

    /// Fan-out map: `folderId → set of session keys subscribed to it`. A
    /// session's `subscribedFolderIds` mirrors the inverse — both are kept
    /// in sync on every subscribe/unsubscribe so broadcast is an O(1) map
    /// lookup + a single iteration.
    private var subscribers: [String: Set<ObjectIdentifier>] = [:]

    /// Persistence key for the chosen port — `0` means "let the OS pick".
    private static let portDefaultsKey = "RemoteServer.port"

    public init(store: MultiFolderStore, identity: RemoteServerIdentity? = nil) {
        self.store = store
        self.identity = identity
        self.routes = RouteTable()
        installDefaultRoutes()
    }

    /// Thrown from `start()` when the host hasn't supplied a TLS identity
    /// (#0112). Hosting is TLS-only in v2.
    public enum StartError: Error, CustomStringConvertible {
        case missingIdentity

        public var description: String {
            switch self {
            case .missingIdentity:
                return "RemoteServer requires a TLS identity. Construct with init(store:identity:)."
            }
        }
    }

    // MARK: Routes

    /// Wires up the v1 REST endpoints (#0080). Each handler returns a
    /// fully-formed `HTTPResponse`; failures map to `404 not_found` or
    /// `500 internal_error` per the issue's error table.
    private func installDefaultRoutes() {
        routes.routes.append(contentsOf: RemoteHandlers.routes(store: store))
    }

    // MARK: Lifecycle

    public func start() throws {
        guard listener == nil else { return }
        guard let identity else {
            throw StartError.missingIdentity
        }

        let savedPort = UInt16(UserDefaults.standard.integer(forKey: Self.portDefaultsKey))
        let port = NWEndpoint.Port(rawValue: savedPort) ?? .any

        // TLS (#0112). The viewer authenticates the host by pinning the
        // cert's SHA-256 fingerprint (#0114), so no client-cert verification
        // is configured server-side.
        let tlsOptions = NWProtocolTLS.Options()
        let secProtocol = tlsOptions.securityProtocolOptions
        let secIdentity = sec_identity_create(identity.secIdentity)
        if let secIdentity {
            sec_protocol_options_set_local_identity(secProtocol, secIdentity)
        } else {
            logger.error("sec_identity_create returned nil — TLS will fail")
        }
        sec_protocol_options_set_min_tls_protocol_version(secProtocol, .TLSv12)

        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
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
        logger.notice("RemoteServer.start requested port=\(savedPort, privacy: .public) tls=true fingerprint=\(identity.fingerprintHex, privacy: .public)")
    }

    public func stop() {
        logger.notice("RemoteServer.stop")
        listener?.cancel()
        listener = nil
        listeningPort = nil
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        // Close any active WS sessions before clearing peer state — the
        // session's close path also clears its entries from the fanout map.
        let openSessions = Array(sessions.values)
        for session in openSessions {
            session.close(code: .goingAway, reason: "server_stopping")
        }
        sessions.removeAll()
        subscribers.removeAll()
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
            let upgraded = await self.handleRequest(on: connection, key: key, remote: remote)
            if !upgraded {
                self.dropConnection(key: key)
            }
        }
    }

    private func dropConnection(key: ObjectIdentifier) {
        if let conn = connections.removeValue(forKey: key) {
            conn.cancel()
        }
        peerInfo.removeValue(forKey: key)
        connectedPeers = Array(peerInfo.values)
    }

    /// Returns `true` when the request was upgraded to a WebSocket session
    /// (so the caller skips `dropConnection`); `false` for the normal
    /// REST request/response path.
    private func handleRequest(on connection: NWConnection, key: ObjectIdentifier, remote: String) async -> Bool {
        let buffer = await readHeaders(on: connection)
        guard let buffer else {
            await send(.badRequest(reason: "read_failed"), on: connection)
            return false
        }
        let request: HTTPRequest
        do {
            request = try HTTPRequestParser.parse(buffer)
        } catch let error as HTTPRequestParser.ParseError {
            await send(.badRequest(reason: "\(error)"), on: connection)
            return false
        } catch {
            await send(.badRequest(reason: "parse_error"), on: connection)
            return false
        }

        let outcome = AuthMiddleware.authenticate(authorizationHeader: request.authorizationHeader)
        if let failure = AuthMiddleware.failureResponse(for: outcome) {
            // Auth runs *before* the upgrade per #0100: a 401 is plain HTTP,
            // not a WS close frame.
            await send(failure, on: connection)
            return false
        }
        // Thread the token's user-chosen name into the peer record so
        // the connected-viewers list (#0092) shows it.
        if case .ok(let record) = outcome, var info = peerInfo[key] {
            info.tokenName = record.name
            peerInfo[key] = info
            connectedPeers = Array(peerInfo.values)
        }

        // WebSocket upgrade path (#0100). The endpoint isn't in the route
        // table — it's a special-cased HTTP→WS hop.
        if request.path == "/v1/events", request.method.caseInsensitiveCompare("GET") == .orderedSame {
            if WebSocketHandshake.isUpgradeRequest(headers: request.headers),
               let clientKey = WebSocketHandshake.header(request.headers, "Sec-WebSocket-Key") {
                let upgraded = await performWebSocketUpgrade(
                    on: connection,
                    key: key,
                    remote: remote,
                    clientKey: clientKey,
                    outcome: outcome
                )
                return upgraded
            } else {
                await send(.badRequest(reason: "invalid_upgrade"), on: connection)
                return false
            }
        }

        guard let (route, captures) = routes.match(method: request.method, path: request.path) else {
            await send(.notFound(), on: connection)
            return false
        }
        do {
            let response = try route.handler(request, captures)
            await send(response, on: connection)

            // Touch the token off the response path so the read isn't
            // blocked on a Keychain write. `AccessToken.touch` is
            // `@concurrent`, so the outer `Task` is just fire-and-forget
            // scheduling — the function declaration enforces the off-
            // actor hop.
            if case .ok(let record) = outcome {
                Task {
                    do {
                        try await AccessToken.touch(hash: record.hash, from: remote)
                    } catch {
                        logger.warning("token touch failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            await send(.internalError(debugMessage: error.localizedDescription), on: connection)
        }
        return false
    }

    /// Performs the 101 handshake on `connection`, registers a
    /// `WebSocketSession`, and hands the connection off to it. Returns
    /// `true` so the caller skips the post-request `dropConnection`.
    private func performWebSocketUpgrade(
        on connection: NWConnection,
        key: ObjectIdentifier,
        remote: String,
        clientKey: String,
        outcome: AuthOutcome
    ) async -> Bool {
        // Flush the 101 response. The connection stays open after this; we
        // pull it out of `connections` (so `stop()` doesn't double-cancel)
        // and let the session own its lifecycle.
        let response = WebSocketHandshake.upgradeResponse(clientKey: clientKey)
        await sendBytes(response, on: connection)
        connections.removeValue(forKey: key)

        let peer = peerInfo[key] ?? PeerInfo(remoteAddress: remote, tokenName: nil, connectedAt: Date())
        let session = WebSocketSession(connection: connection, peer: peer)
        sessions[key] = session
        session.onSubscribe = { [weak self] session, ids in
            self?.handleSubscribe(session: session, key: key, ids: ids)
        }
        session.onUnsubscribe = { [weak self] session, ids in
            self?.handleUnsubscribe(session: session, key: key, ids: ids)
        }
        session.onClose = { [weak self] _ in
            self?.handleSessionClose(key: key)
        }

        // Greet the viewer with the hello frame so it can render the host
        // display name and verify protocol version immediately.
        session.send(.hello(displayName: store.hostDisplayName))
        session.start()

        // Touch the token off the response path. `@concurrent` on the
        // async overload forces execution off MainActor — see #0122.
        if case .ok(let record) = outcome {
            Task {
                do {
                    try await AccessToken.touch(hash: record.hash, from: remote)
                } catch {
                    logger.warning("token touch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        logger.notice("ws upgraded peer=\(remote, privacy: .public)")
        return true
    }

    // MARK: - WS subscription / fanout

    private func handleSubscribe(session: WebSocketSession, key: ObjectIdentifier, ids: [String]) {
        for id in ids {
            subscribers[id, default: []].insert(key)
        }
    }

    private func handleUnsubscribe(session: WebSocketSession, key: ObjectIdentifier, ids: [String]) {
        for id in ids {
            subscribers[id]?.remove(key)
            if subscribers[id]?.isEmpty == true {
                subscribers.removeValue(forKey: id)
            }
        }
    }

    private func handleSessionClose(key: ObjectIdentifier) {
        // Drop from fanout, peer list, session map. The session has
        // already cancelled the underlying connection on its own.
        if let session = sessions.removeValue(forKey: key) {
            for id in session.subscribedFolderIds {
                subscribers[id]?.remove(key)
                if subscribers[id]?.isEmpty == true {
                    subscribers.removeValue(forKey: id)
                }
            }
        }
        peerInfo.removeValue(forKey: key)
        connectedPeers = Array(peerInfo.values)
    }

    /// Server-owned broadcast entry point. Iterates the fan-out map and
    /// hands the event to each subscribed session's send queue. Called by
    /// `RemoteHostController` after an `IssueStore.onReloadBroadcast` tick.
    public func broadcast(_ event: RemoteEvent, toFolderId folderId: String) {
        guard let keys = subscribers[folderId], !keys.isEmpty else { return }
        for key in keys {
            sessions[key]?.send(event)
        }
    }

    /// Drop all subscriptions to `folderId` (host flipped the share toggle
    /// off, or the bookmark went stale). Emits `unsubscribed` to each
    /// subscriber and removes them from the map.
    public func unshareFolder(folderId: String, reason: String) {
        guard let keys = subscribers.removeValue(forKey: folderId) else { return }
        for key in keys {
            sessions[key]?.dropSubscription(folderId: folderId, reason: reason)
        }
    }

    /// Force-close every WS session — used when the host revokes the
    /// underlying access token (#0084). The wire code is 4001
    /// "token revoked"; viewers surface the expired-token UI (#0104).
    /// Optional `predicate` lets callers target a specific token (e.g.
    /// match by token name); when nil every session is closed.
    public func closeSessions(matching predicate: ((WebSocketSession) -> Bool)? = nil, code: WebSocketCloseCode = .tokenRevoked) {
        let open = Array(sessions.values)
        for session in open {
            if predicate?(session) ?? true {
                session.close(code: code, reason: "token_revoked")
            }
        }
    }

    /// Test seam — surfaces the count of subscribers to a given folder.
    public var _subscriberCountByFolder: [String: Int] {
        var out: [String: Int] = [:]
        for (id, keys) in subscribers { out[id] = keys.count }
        return out
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
