import Foundation
import os.log

#if os(macOS) || os(iOS)

nonisolated private let sourceLogger = Logger(subsystem: Logging.subsystem, category: "RemoteHostIssueSource")

/// Connection state for the remote source, used by the disconnect/expired
/// UI (#0104). Transitions are driven by `handleWebSocketEvent` and the
/// HTTP reload path; views bind to `IssueStore.remoteConnectionState` and
/// render the matching banner.
enum RemoteConnectionState: Equatable, Sendable {
    case connected
    case reconnecting(since: Date)
    case disconnected(reason: String)
    case tokenInvalid
    case folderUnavailable
}

/// Lifecycle events the source publishes through `eventStream` (#0094).
/// `RemoteIssueSourceEvent.reloaded` is informational — the actual issues array has
/// already been updated; SwiftUI views observe `IssueStore` for the
/// payload. The other cases are state transitions the viewer UI needs to
/// react to:
///
/// - `.tokenInvalid` — host returned 401; surface the expired/revoked
///   token UI (#0104) and stop the source.
/// - `.folderUnavailable` — host returned 404 on the folder path; the
///   picker should fall back to find-by-name (#0098).
/// - `.disconnected` — transport-level failure; reconnect logic (#0103)
///   re-creates the source.
/// - `.issueChanged(id:)` — single-row update after a lazy body fetch.
enum RemoteIssueSourceEvent: Sendable, Equatable {
    case reloaded
    case issueChanged(id: String)
    case disconnected
    case tokenInvalid
    case folderUnavailable
}

/// `IssueSource` (from #0077) backed by a remote Issues.app host. Talks
/// HTTP today; the WebSocket subscription path is stubbed out behind a
/// `// TODO(#0102)` marker — for now `reload()` is the only refresh.
///
/// To `IssueStore` and the views a remote folder looks identical to a
/// local one: same `[Issue]` array, same `onUpdate` callback, same
/// lifecycle methods. That's the whole point of the #0077 protocol.
@MainActor
final class RemoteHostIssueSource: IssueSource {

    /// URL scheme used for the synthetic `folderURL` exposed to the rest of
    /// the app (#0094). Views detect a remote tab by checking
    /// `store.folderURL.scheme == RemoteHostIssueSource.urlScheme` instead
    /// of casting through the source existential.
    static let urlScheme = "issues-remote"

    // MARK: - IssueSource conformance (observable state)

    var folderURL: URL { syntheticFolderURL }

    /// User-visible label. Populated from `FolderInfo.name` after the
    /// first `start()` / `reload()`; falls back to the host:port until
    /// then so a slow first response doesn't render blank.
    private(set) var displayName: String

    private(set) var projectMetadata: ProjectMetadata?

    /// Remote sources don't have a security-scoped bookmark — they
    /// publish a stable id directly. The `IssueStore.folderId` getter
    /// hashes whatever bytes are here; we feed it the canonical
    /// `<hostId>|<folderId>` so a future "remote tab id" (#0099) can
    /// share the same identifier.
    let bookmarkData: Data?

    /// Diagnostic label — used in log lines and the (eventual) remote
    /// tab subtitle. `<displayName>@<host>` so multi-host streams stay
    /// readable.
    var repoName: String { displayName }

    private(set) var issues: [Issue] = []
    private(set) var lintFindings: [LintFinding] = []
    private(set) var loadError: String?
    private(set) var folderInvalidated: Bool = false
    /// Current connection state (#0104). Mutated as events arrive on the
    /// WS stream and as HTTP reloads succeed/fail. Views observe this
    /// through `IssueStore.remoteConnectionState` for the banner.
    private(set) var connectionState: RemoteConnectionState = .connected
    var onUpdate: ((any IssueSource) -> Void)?

    // MARK: - Connection identity

    let host: String
    let port: UInt16
    private(set) var folderId: String
    /// Name seeded at construction time (from the wire `FolderInfo.name`
    /// captured when the user opened the tab). Used by the find-by-name
    /// rebind path (#0103) when the persisted `folderId` returns 404.
    private let nameHint: String?
    private let syntheticFolderURL: URL

    // MARK: - Internals

    private let client: RemoteClientProtocol
    private let token: String
    private var bodyCache: [String: String] = [:]
    /// `(id → wire modifiedAt)` from the last metadata fetch. Used to
    /// invalidate `bodyCache` entries on reload — if the wire mtime moved
    /// we drop the cached body so the next selection re-fetches.
    private var lastSeenMtime: [String: Date] = [:]
    private var inFlightReloadTask: Task<Void, Never>?
    /// WS transport (#0102). Created on `start()` after the initial reload;
    /// the source consumes events from `websocket.events` and translates
    /// to `RemoteIssueSourceEvent` for the viewer UI.
    private var websocket: RemoteWebSocket?
    private var websocketListener: Task<Void, Never>?

    /// AsyncStream of lifecycle events. The viewer UI consumes this to
    /// drive the disconnected / expired-token surfaces (#0104).
    let eventStream: AsyncStream<RemoteIssueSourceEvent>
    private let eventContinuation: AsyncStream<RemoteIssueSourceEvent>.Continuation

    // MARK: - Init

    init(
        host: String,
        port: UInt16,
        token: String,
        folderId: String,
        displayName: String? = nil,
        client: RemoteClientProtocol? = nil
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.folderId = folderId
        // Seed `displayName` from the caller (the picker already fetched the
        // wire `FolderInfo.name` before deciding to open a tab) so the chip
        // shows the right label before the first reload finishes. Falls back
        // to `host:port` until the source's own reload lands a value.
        self.displayName = displayName?.isEmpty == false ? displayName! : "\(host):\(port)"
        self.nameHint = displayName?.isEmpty == false ? displayName : nil
        self.bookmarkData = Data("remote:\(host):\(port)|\(folderId)".utf8)
        self.syntheticFolderURL = URL(string: "\(Self.urlScheme)://\(host):\(port)/\(folderId)")
            ?? URL(fileURLWithPath: "/tmp/issues-remote-\(folderId)")
        if let client {
            self.client = client
        } else {
            self.client = URLSessionRemoteClient(host: host, port: port, token: token)
        }
        var continuation: AsyncStream<RemoteIssueSourceEvent>.Continuation!
        self.eventStream = AsyncStream<RemoteIssueSourceEvent> { c in continuation = c }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - Lifecycle

    func start() {
        sourceLogger.notice("[\(self.repoName, privacy: .public)] start host=\(self.host, privacy: .public):\(self.port, privacy: .public) folder=\(self.folderId, privacy: .public)")
        reload()
        startWebSocketIfNeeded()
    }

    func stop() {
        sourceLogger.notice("[\(self.repoName, privacy: .public)] stop")
        inFlightReloadTask?.cancel()
        inFlightReloadTask = nil
        websocketListener?.cancel()
        websocketListener = nil
        websocket?.stop()
        websocket = nil
    }

    /// Opens the WS once per source lifetime. Re-entrant: a second call
    /// while a socket is already running is a no-op.
    private func startWebSocketIfNeeded() {
        guard websocket == nil else { return }
        let ws = RemoteWebSocket(host: host, port: port, token: token, folderId: folderId)
        websocket = ws
        ws.start()
        websocketListener = Task { [weak self, weak ws] in
            guard let stream = ws?.events else { return }
            for await event in stream {
                guard let self else { break }
                await MainActor.run {
                    self.handleWebSocketEvent(event)
                }
            }
        }
    }

    private func handleWebSocketEvent(_ event: RemoteWebSocketEvent) {
        switch event {
        case .event(let wire):
            switch wire.type {
            case .reload:
                if wire.folderId == folderId {
                    reload()
                }
            case .update:
                if let id = wire.id, wire.folderId == folderId {
                    // Drop the cached body so the next selection re-fetches.
                    bodyCache.removeValue(forKey: id)
                    lastSeenMtime.removeValue(forKey: id)
                    // Re-pull the full metadata list to pick up status /
                    // mtime changes; the next view tick re-renders.
                    reload()
                    eventContinuation.yield(.issueChanged(id: id))
                }
            case .delete:
                if let id = wire.id, wire.folderId == folderId {
                    bodyCache.removeValue(forKey: id)
                    lastSeenMtime.removeValue(forKey: id)
                    issues.removeAll { $0.id == id }
                    onUpdate?(self)
                    eventContinuation.yield(.issueChanged(id: id))
                }
            case .unsubscribed:
                if wire.folderId == folderId {
                    folderInvalidated = true
                    connectionState = .folderUnavailable
                    onUpdate?(self)
                    eventContinuation.yield(.folderUnavailable)
                }
            case .hello:
                connectionState = .connected
                onUpdate?(self)
            case .pong:
                break
            }
        case .disconnected:
            loadError = "Connection to host lost — reconnecting…"
            connectionState = .reconnecting(since: Date())
            onUpdate?(self)
            eventContinuation.yield(.disconnected)
        case .tokenInvalid:
            loadError = "Token rejected by host."
            connectionState = .tokenInvalid
            onUpdate?(self)
            eventContinuation.yield(.tokenInvalid)
            // Don't keep retrying — stop the socket entirely.
            websocketListener?.cancel()
            websocketListener = nil
            websocket?.stop()
            websocket = nil
        }
    }

    func reload() {
        inFlightReloadTask?.cancel()
        inFlightReloadTask = Task { [weak self] in
            await self?.performReload()
        }
    }

    private func performReload() async {
        do {
            let info = try await client.fetchFolder(id: folderId)
            let metas = try await client.fetchIssues(folderId: folderId)
            try Task.checkCancellation()

            displayName = info.name
            projectMetadata = ProjectMetadata(name: info.name, url: info.url)

            // Map wire metadata to local Issue values. Body is empty
            // until `fetchBody(for:)` is called; the swimlane preview
            // shows "—" until then. Lint findings are not transmitted
            // (lint runs only on the host); leave the array empty.
            let newIssues = metas.map { meta in
                Issue(
                    id: meta.id,
                    title: meta.title,
                    status: IssueStatus(raw: meta.status),
                    statusRaw: meta.status,
                    module: meta.modules.joined(separator: " / "),
                    platform: meta.platform,
                    firstSeen: meta.firstSeen,
                    firstSeenRaw: meta.firstSeen.map(Self.shortDate) ?? "",
                    closed: meta.closedAt,
                    closedRaw: meta.closedAt.map(Self.shortDate) ?? "",
                    description: bodyCache[meta.id] ?? "",
                    fileURL: syntheticFolderURL.appendingPathComponent("\(meta.id).md"),
                    modifiedAt: meta.modifiedAt,
                    hasAttachments: meta.hasAttachments
                )
            }
            // Invalidate body cache entries whose mtime moved.
            for meta in metas {
                if let previous = lastSeenMtime[meta.id], previous != meta.modifiedAt {
                    bodyCache.removeValue(forKey: meta.id)
                }
                lastSeenMtime[meta.id] = meta.modifiedAt
            }
            // Drop bodies for issues that disappeared.
            let liveIds = Set(metas.map(\.id))
            bodyCache = bodyCache.filter { liveIds.contains($0.key) }

            issues = newIssues
            loadError = nil
            folderInvalidated = false
            connectionState = .connected
            onUpdate?(self)
            eventContinuation.yield(.reloaded)
        } catch is CancellationError {
            // Caller-driven cancellation. No state change; the next
            // reload() will repopulate.
        } catch RemoteClientError.unauthorized {
            sourceLogger.warning("[\(self.repoName, privacy: .public)] unauthorized — token invalid")
            loadError = "Token rejected by host."
            connectionState = .tokenInvalid
            onUpdate?(self)
            eventContinuation.yield(.tokenInvalid)
            inFlightReloadTask = nil
        } catch RemoteClientError.folderNotFound {
            sourceLogger.warning("[\(self.repoName, privacy: .public)] folder unavailable on host — attempting find-by-name rebind")
            if await attemptFindByNameRebind() {
                // Rebind succeeded; retry the reload with the new folderId
                // by yielding back into the reload pipeline.
                reload()
                return
            }
            loadError = "Folder no longer available on host."
            folderInvalidated = true
            connectionState = .folderUnavailable
            onUpdate?(self)
            eventContinuation.yield(.folderUnavailable)
            inFlightReloadTask = nil
        } catch let error as RemoteClientError {
            sourceLogger.warning("[\(self.repoName, privacy: .public)] remote error \(String(describing: error), privacy: .public)")
            loadError = "Couldn't reach host."
            connectionState = .disconnected(reason: String(describing: error))
            onUpdate?(self)
            eventContinuation.yield(.disconnected)
        } catch {
            sourceLogger.warning("[\(self.repoName, privacy: .public)] unexpected error \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
            connectionState = .disconnected(reason: error.localizedDescription)
            onUpdate?(self)
            eventContinuation.yield(.disconnected)
        }
    }

    // MARK: - Body fetching (spec §"Body fetching")

    /// Returns the cached body for `id` if present, otherwise fetches it
    /// via `/v1/folders/{folderId}/issues/{id}`, stuffs the result into
    /// the in-memory `Issue.description`, fires `onUpdate`, and yields
    /// `.issueChanged(id)`. Subsequent calls for the same id are a
    /// cache hit (no network).
    func fetchBody(for id: String) async throws -> String {
        if let cached = bodyCache[id] {
            return cached
        }
        let detail: IssueDetail
        do {
            detail = try await client.fetchIssueDetail(folderId: folderId, id: id)
        } catch RemoteClientError.unauthorized {
            loadError = "Token rejected by host."
            onUpdate?(self)
            eventContinuation.yield(.tokenInvalid)
            throw RemoteClientError.unauthorized
        } catch RemoteClientError.notFound {
            // The issue vanished between the metadata fetch and this
            // body fetch. Drop the row and surface the change.
            issues.removeAll { $0.id == id }
            bodyCache.removeValue(forKey: id)
            lastSeenMtime.removeValue(forKey: id)
            onUpdate?(self)
            eventContinuation.yield(.issueChanged(id: id))
            throw RemoteClientError.notFound
        } catch let error as RemoteClientError {
            loadError = "Couldn't fetch issue body."
            onUpdate?(self)
            eventContinuation.yield(.disconnected)
            throw error
        }
        bodyCache[id] = detail.body
        if let idx = issues.firstIndex(where: { $0.id == id }) {
            let prev = issues[idx]
            issues[idx] = Issue(
                id: prev.id,
                title: prev.title,
                status: prev.status,
                statusRaw: prev.statusRaw,
                module: prev.module,
                platform: prev.platform,
                firstSeen: prev.firstSeen,
                firstSeenRaw: prev.firstSeenRaw,
                closed: prev.closed,
                closedRaw: prev.closedRaw,
                description: detail.body,
                fileURL: prev.fileURL,
                modifiedAt: prev.modifiedAt,
                hasAttachments: prev.hasAttachments
            )
            onUpdate?(self)
            eventContinuation.yield(.issueChanged(id: id))
        }
        return detail.body
    }

    /// `true` when the body for `id` is already cached. Used by the
    /// viewer UI to render an instant detail panel vs. a placeholder.
    func hasCachedBody(for id: String) -> Bool {
        bodyCache[id] != nil
    }

    // MARK: - Find-by-name rebind (#0103)

    /// Spec §"Timeouts and fallback": if `/v1/folders/{folderId}` returns
    /// 404 (the host renamed/re-bookmarked the folder so its id changed),
    /// best-effort fetch the full folder list and look for a single name
    /// match. On match, swap `folderId` and let the caller retry the
    /// reload. On zero/multiple matches, return false and the caller
    /// surfaces `.folderUnavailable`.
    private func attemptFindByNameRebind() async -> Bool {
        guard let nameHint, !nameHint.isEmpty else { return false }
        let candidates: [FolderInfo]
        do {
            candidates = try await client.fetchFolders()
        } catch {
            sourceLogger.warning("[\(self.repoName, privacy: .public)] find-by-name fetch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let matches = candidates.filter { $0.name == nameHint }
        guard matches.count == 1, let match = matches.first else {
            sourceLogger.warning("[\(self.repoName, privacy: .public)] find-by-name: \(matches.count, privacy: .public) candidates for name=\(self.nameHint ?? "?", privacy: .public)")
            return false
        }
        sourceLogger.notice("[\(self.repoName, privacy: .public)] find-by-name rebind \(self.folderId, privacy: .public) → \(match.id, privacy: .public)")
        folderId = match.id
        return true
    }

    // MARK: - Helpers

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

#endif
