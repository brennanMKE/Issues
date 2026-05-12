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
final class RemoteWebSocket {

    // MARK: - Public

    /// Stream of received `RemoteEvent`s plus a synthetic `.disconnected`
    /// signal (we reuse the wire shape's missing/null shape so callers can
    /// branch on `event.type`).
    let events: AsyncStream<RemoteWebSocketEvent>

    private let eventContinuation: AsyncStream<RemoteWebSocketEvent>.Continuation

    /// Active reconnect-backoff state, exposed only for testability. Production
    /// code reads through `events`.
    private(set) var attemptCount: Int = 0

    // MARK: - Configuration

    let host: String
    let port: UInt16
    let token: String
    let folderId: String
    private let urlSession: URLSession
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

    init(
        host: String,
        port: UInt16,
        token: String,
        folderId: String,
        urlSession: URLSession = .shared,
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
        self.urlSession = urlSession
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

    func start() {
        guard !isStopped else { return }
        // Re-entrant: a fresh start() cancels any in-flight reconnect timer.
        reconnectTimer?.cancel()
        reconnectTimer = nil
        openConnection()
    }

    func stop() {
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
        guard let url = Self.url(host: host, port: port) else {
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
        // URLSessionWebSocketTask doesn't always surface close codes; we
        // probe for the tokenRevoked sentinel via the `closeCode` attribute
        // before tearing down.
        let closeCode = task?.closeCode ?? .invalid
        task = nil
        pingTimer?.cancel()
        pingTimer = nil
        pongDeadline = nil
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
    func nextBackoffDelay(forAttempt attempt: Int) -> TimeInterval {
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
                if let pongDeadline, pongDeadline <= Date() {
                    _ = pongDeadline
                    wsLogger.notice("ws pong timeout — forcing reconnect")
                    self.task?.cancel(with: .abnormalClosure, reason: nil)
                    self.handleTransportFailure(error: URLError(.timedOut))
                }
            }
        }
        _ = task
    }

    // MARK: - URL

    /// Builds the ws:// URL. IPv6 literals are bracketed automatically.
    static func url(host: String, port: UInt16) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let bracketed: String
        if trimmed.contains(":") && !trimmed.hasPrefix("[") {
            bracketed = "[\(trimmed)]"
        } else {
            bracketed = trimmed
        }
        return URL(string: "ws://\(bracketed):\(port)/v1/events")
    }
}

/// Event surfaced by `RemoteWebSocket.events`. Distinct from the wire
/// `RemoteEvent` (which is decoded then wrapped here) so the source can
/// distinguish "got a wire event" from "transport failure / token revoked"
/// without having to invent special wire shapes.
enum RemoteWebSocketEvent: Sendable {
    case event(RemoteEvent)
    case disconnected
    case tokenInvalid
}

#endif
