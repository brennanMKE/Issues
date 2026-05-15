import Foundation
import os.log

#if os(macOS) || os(iOS)

nonisolated private let wsLogger = Logger(subsystem: Logging.subsystem, category: "RemoteWebSocket")

/// Viewer-side WebSocket wrapper used by `RemoteHostIssueSource` (#0102).
/// Wraps `URLSessionWebSocketTask` with bearer auth, automatic reconnect on
/// transport failures, ping/pong watchdog, and a `RemoteEvent` stream.
///
/// Lifecycle:
///   `start()`  → opens the socket, sends `subscribe` for `folderId`, begins
///                receiving frames and pinging.
///   `stop()`   → cancels the in-flight task and any reconnect timer. Idempotent.
///
/// Reconnect strategy:
///   - 1s, 2s, 4s, 8s, 16s with ±25% jitter, capped at 30s.
///   - Reset to 1s on the first successful open.
///   - Stop reconnecting on close code 4001 (token revoked) or `stop()`.
///
/// Events surface on `events`. The source consumes this stream and translates
/// to its own `RemoteIssueSourceEvent` channel.
@MainActor
public final class RemoteWebSocket {

    // MARK: - Public

    /// Stream of received `RemoteEvent`s plus a synthetic `.disconnected`
    /// signal (we reuse the wire shape's missing/null shape so callers can
    /// branch on `event.type`).
    public let events: AsyncStream<RemoteWebSocketEvent>

    private let eventContinuation: AsyncStream<RemoteWebSocketEvent>.Continuation

    /// Active reconnect-backoff state, exposed only for testability. Production
    /// code reads through `events`.
    public private(set) var attemptCount: Int = 0

    // MARK: - Configuration

    public let host: String
    public let port: UInt16
    public let token: String
    public let folderId: String
    /// Pinned fingerprint (#0114). Empty for the legacy pre-TLS path
    /// (so existing tests / call sites without a fingerprint keep
    /// compiling); production callers must pass a real 64-hex value.
    public let fingerprint: String
    private let urlSession: URLSession
    private let pinDelegate: PinnedHostSessionDelegate?
    private let pingInterval: TimeInterval
    private let pongTimeout: TimeInterval
    private let backoffSchedule: [TimeInterval]
    private let backoffCap: TimeInterval
    private let jitterFraction: Double

    // MARK: - Internal task state

    private var task: URLSessionWebSocketTask?
    private var reconnectTimer: Task<Void, Never>?
    private var pingTimer: Task<Void, Never>?
    private var pongDeadline: Date?
    private var isStopped: Bool = false

    public init(
        host: String,
        port: UInt16,
        token: String,
        folderId: String,
        fingerprint: String = "",
        urlSession: URLSession? = nil,
        pingInterval: TimeInterval = 25,
        pongTimeout: TimeInterval = 10,
        backoffSchedule: [TimeInterval] = [1, 2, 4, 8, 16],
        backoffCap: TimeInterval = 30,
        jitterFraction: Double = 0.25
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.folderId = folderId
        self.fingerprint = fingerprint
        if let urlSession {
            self.urlSession = urlSession
            self.pinDelegate = nil
        } else if !fingerprint.isEmpty {
            let delegate = PinnedHostSessionDelegate(expectedFingerprint: fingerprint)
            self.pinDelegate = delegate
            self.urlSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        } else {
            self.pinDelegate = nil
            self.urlSession = .shared
        }
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
        self.backoffSchedule = backoffSchedule
        self.backoffCap = backoffCap
        self.jitterFraction = jitterFraction

        var continuation: AsyncStream<RemoteWebSocketEvent>.Continuation!
        self.events = AsyncStream<RemoteWebSocketEvent> { c in continuation = c }
        self.eventContinuation = continuation
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isStopped else { return }
        // Re-entrant: a fresh start() cancels any in-flight reconnect timer.
        reconnectTimer?.cancel()
        reconnectTimer = nil
        openConnection()
    }

    public func stop() {
        guard !isStopped else { return }
        isStopped = true
        wsLogger.notice("ws stop host=\(self.host, privacy: .public):\(self.port, privacy: .public)")
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        reconnectTimer?.cancel()
        reconnectTimer = nil
        pingTimer?.cancel()
        pingTimer = nil
        eventContinuation.finish()
    }

    // MARK: - Connection

    private func openConnection() {
        guard !isStopped else { return }
        // #0114: TLS-only wire when a fingerprint is pinned. The empty-
        // fingerprint path stays on `ws://` for legacy tests / pre-TLS
        // call sites.
        let scheme = fingerprint.isEmpty ? "ws" : "wss"
        guard let url = Self.url(host: host, port: port, scheme: scheme) else {
            wsLogger.warning("ws open: invalid url for \(self.host, privacy: .public):\(self.port, privacy: .public)")
            scheduleReconnect()
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = urlSession.webSocketTask(with: request)
        self.task = task
        task.resume()
        wsLogger.notice("ws open host=\(self.host, privacy: .public):\(self.port, privacy: .public) attempt=\(self.attemptCount, privacy: .public)")
        sendSubscribe()
        startPingLoop()
        receiveLoop()
    }

    private func sendSubscribe() {
        let command = RemoteCommand.subscribe(folderIds: [folderId])
        sendCommand(command)
    }

    private func sendCommand(_ command: RemoteCommand) {
        guard let task else { return }
        do {
            let data = try RemoteProtocol.encoder.encode(command)
            guard let text = String(data: data, encoding: .utf8) else { return }
            task.send(.string(text)) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.handleTransportFailure(error: error)
                    }
                }
            }
        } catch {
            wsLogger.warning("ws encode command failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleReceive(result)
            }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .failure(let error):
            handleTransportFailure(error: error)
        case .success(let message):
            // First successful frame on a fresh connection resets backoff.
            attemptCount = 0
            switch message {
            case .string(let text):
                if let data = text.data(using: .utf8) { decodeFrame(data) }
            case .data(let data):
                decodeFrame(data)
            @unknown default:
                break
            }
            // Keep listening.
            receiveLoop()
        }
    }

    private func decodeFrame(_ data: Data) {
        do {
            let event = try RemoteProtocol.decoder.decode(RemoteEvent.self, from: data)
            // Pong frames are kept off the user-visible stream; they reset
            // the pong deadline so the next ping cycle gets a fresh window.
            if event.type == .pong {
                pongDeadline = nil
                return
            }
            eventContinuation.yield(.event(event))
        } catch {
            wsLogger.warning("ws decode frame failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTransportFailure(error: Error) {
        wsLogger.warning("ws transport failure: \(error.localizedDescription, privacy: .public)")
        let closeCode = task?.closeCode ?? .invalid
        task = nil
        pingTimer?.cancel()
        pingTimer = nil
        pongDeadline = nil
        // Cert-pin failure surfaces as URLError.cancelled or
        // .serverCertificateUntrusted from the URLSession delegate
        // (#0114). Don't retry — pin failure is recoverable only via
        // re-paste, the same as token revocation.
        if let urlError = error as? URLError,
           !fingerprint.isEmpty,
           (urlError.code == .cancelled || urlError.code == .serverCertificateUntrusted) {
            wsLogger.notice("ws closed on cert-pin failure — surfacing fingerprintMismatch")
            eventContinuation.yield(.fingerprintMismatch)
            return
        }
        // URLSessionWebSocketTask doesn't always surface close codes; we
        // probe for the tokenRevoked sentinel via the `closeCode` attribute
        // before tearing down.
        if closeCode.rawValue == 4001 {
            wsLogger.notice("ws closed with token-revoked (4001) — surfacing tokenInvalid")
            eventContinuation.yield(.tokenInvalid)
            return
        }
        eventContinuation.yield(.disconnected)
        scheduleReconnect()
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !isStopped else { return }
        let delay = nextBackoffDelay(forAttempt: attemptCount)
        attemptCount += 1
        wsLogger.notice("ws reconnect in \(String(format: "%.1f", delay), privacy: .public)s (attempt=\(self.attemptCount, privacy: .public))")
        reconnectTimer?.cancel()
        reconnectTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            await MainActor.run {
                self.reconnectTimer = nil
                self.openConnection()
            }
        }
    }

    /// Pulls the next delay from `backoffSchedule` (using `attempt` as the
    /// index, clamped to the schedule's end), caps it, and applies
    /// ±`jitterFraction` random jitter. Exposed for unit tests.
    public func nextBackoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let idx = min(max(attempt, 0), backoffSchedule.count - 1)
        let base = backoffSchedule[idx]
        let capped = min(base, backoffCap)
        let jitter = Double.random(in: -jitterFraction...jitterFraction)
        let value = capped * (1.0 + jitter)
        return max(0.1, value)
    }

    // MARK: - Pings

    private func startPingLoop() {
        pingTimer?.cancel()
        pingTimer = Task { [weak self] in
            while let self, await !self.isStopped, await self.task != nil {
                let interval = await self.pingInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await MainActor.run {
                    self.tickPing()
                }
            }
        }
    }

    private func tickPing() {
        guard let task, !isStopped else { return }
        // Application-level ping per the spec (RemoteCommand.ping). The host
        // mirrors with `pong`; missing pong within `pongTimeout` triggers a
        // forced close.
        sendCommand(.ping)
        let deadline = Date().addingTimeInterval(pongTimeout)
        pongDeadline = deadline
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.pongTimeout ?? 10 * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                if let pongDeadline = self.pongDeadline, pongDeadline <= Date() {
                    wsLogger.notice("ws pong timeout — forcing reconnect")
                    self.task?.cancel(with: .abnormalClosure, reason: nil)
                    self.handleTransportFailure(error: URLError(.timedOut))
                }
            }
        }
        _ = task
    }

    // MARK: - URL

    /// Builds the ws:// or wss:// URL. IPv6 literals are bracketed
    /// automatically. The scheme defaults to `wss` for v2 (#0114); the
    /// `scheme:` parameter is exposed for legacy callers / tests.
    public static func url(host: String, port: UInt16, scheme: String = "wss") -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let bracketed: String
        if trimmed.contains(":") && !trimmed.hasPrefix("[") {
            bracketed = "[\(trimmed)]"
        } else {
            bracketed = trimmed
        }
        return URL(string: "\(scheme)://\(bracketed):\(port)/v1/events")
    }
}

/// Event surfaced by `RemoteWebSocket.events`. Distinct from the wire
/// `RemoteEvent` (which is decoded then wrapped here) so the source can
/// distinguish "got a wire event" from "transport failure / token revoked"
/// without having to invent special wire shapes.
public enum RemoteWebSocketEvent: Sendable {
    case event(RemoteEvent)
    case disconnected
    case tokenInvalid
    /// TLS handshake completed but the presented cert's fingerprint
    /// didn't match what the viewer pinned. Source surfaces this up
    /// the chain to `.fingerprintMismatch` and the UI banner (#0115).
    case fingerprintMismatch
}

#endif
