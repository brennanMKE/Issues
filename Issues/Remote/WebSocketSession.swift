import Foundation
import CryptoKit
import os.log

#if os(macOS)
import Network
#endif

/// RFC 6455 framing primitives plus per-connection session state used by
/// `RemoteServer` to serve `/v1/events` (#0100, #0101). No third-party
/// dependencies — `Network.framework` for I/O, `CryptoKit` for the
/// `Sec-WebSocket-Accept` handshake hash, `Foundation` for everything else.
///
/// The framing layer is intentionally split into small pure helpers
/// (`WebSocketHandshake`, `WebSocketFrame`) so the tests can exercise them
/// without standing up a real `NWConnection`.

/// Standard close codes used by the host. Numeric raw values match the
/// wire codes the viewer will see.
enum WebSocketCloseCode: UInt16 {
    case normal = 1000
    case goingAway = 1001
    case protocolError = 1002
    case unsupportedData = 1003
    case policyViolation = 1008
    case internalError = 1011
    /// 4xxx range is reserved for application use. The host emits 4001 when a
    /// token is revoked mid-session (#0084 / #0100 spec).
    case tokenRevoked = 4001
}

// MARK: - Handshake

/// Pure helpers for the HTTP→WS upgrade. The 16-byte GUID is fixed by RFC
/// 6455 §4.1 and combined with the client's `Sec-WebSocket-Key` to compute
/// the response `Sec-WebSocket-Accept` header.
enum WebSocketHandshake {

    /// Magic GUID per RFC 6455 §1.3. Concatenated with the client's key
    /// before SHA-1 to derive the accept value.
    static let acceptGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// Computes the `Sec-WebSocket-Accept` value for a given client key.
    /// Returns nil only if the input isn't UTF-8 (which it always is for
    /// HTTP headers); callers can `??` an empty string defensively.
    static func acceptValue(forKey clientKey: String) -> String {
        let combined = clientKey + acceptGUID
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }

    /// `true` when the supplied request headers carry the standard WS
    /// upgrade values. `Sec-WebSocket-Key` and `Sec-WebSocket-Version` are
    /// both required by RFC 6455; we only support `13` (the only version).
    static func isUpgradeRequest(headers: [String: String]) -> Bool {
        guard let upgrade = header(headers, "Upgrade"),
              upgrade.lowercased() == "websocket" else { return false }
        guard let connection = header(headers, "Connection"),
              connection.lowercased().contains("upgrade") else { return false }
        guard let version = header(headers, "Sec-WebSocket-Version"),
              version.trimmingCharacters(in: .whitespaces) == "13" else { return false }
        guard let key = header(headers, "Sec-WebSocket-Key"),
              !key.isEmpty else { return false }
        return true
    }

    /// Extract a header by case-insensitive name.
    static func header(_ headers: [String: String], _ name: String) -> String? {
        for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame {
            return value
        }
        return nil
    }

    /// Serializes the 101 response to wire bytes.
    static func upgradeResponse(clientKey: String) -> Data {
        let accept = acceptValue(forKey: clientKey)
        var lines: [String] = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)"
        ]
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }
}

// MARK: - Frame model

/// One decoded WS frame. v1 only handles single-frame messages (no
/// continuation / fragmentation); `fin` is always true on the inbound
/// path and we close 1002 if a client sends a fragment.
struct WebSocketFrame: Equatable {
    enum Opcode: UInt8 {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    var fin: Bool
    var opcode: Opcode
    var payload: Data

    /// Inbound text payload as a UTF-8 string, or nil if the bytes aren't
    /// valid UTF-8. Only meaningful for `.text`.
    var textPayload: String? {
        guard opcode == .text else { return nil }
        return String(data: payload, encoding: .utf8)
    }
}

// MARK: - Framing

/// Encoder/decoder pair for the RFC 6455 wire format. Client→server frames
/// are always masked (4-byte XOR over the payload); server→client frames
/// are never masked. The decoder enforces that direction.
enum WebSocketFraming {

    enum DecodeError: Error, Equatable {
        case incompleteHeader
        case incompletePayload
        case clientFrameNotMasked
        case unsupportedOpcode(UInt8)
        case payloadTooLarge
        case reservedBitsSet
    }

    /// Decode one inbound frame starting at the head of `data`. Returns the
    /// frame plus the number of bytes consumed. `.incompleteHeader` /
    /// `.incompletePayload` mean the caller should wait for more bytes;
    /// other errors mean the connection should close with protocolError.
    /// Maximum payload size in bytes (1 MiB). Client→server text frames are
    /// small JSON commands; anything bigger is a misuse and we close 1009.
    static let maxPayloadSize: Int = 1 << 20

    static func decodeClientFrame(from data: Data) throws -> (frame: WebSocketFrame, consumed: Int) {
        guard data.count >= 2 else { throw DecodeError.incompleteHeader }
        let bytes = [UInt8](data)
        let b0 = bytes[0]
        let b1 = bytes[1]
        let fin = (b0 & 0x80) != 0
        // We reject reserved bits — no extension negotiation in v1.
        if (b0 & 0x70) != 0 { throw DecodeError.reservedBitsSet }
        let rawOpcode = b0 & 0x0F
        guard let opcode = WebSocketFrame.Opcode(rawValue: rawOpcode) else {
            throw DecodeError.unsupportedOpcode(rawOpcode)
        }
        let masked = (b1 & 0x80) != 0
        guard masked else { throw DecodeError.clientFrameNotMasked }
        var cursor = 2
        var payloadLength = Int(b1 & 0x7F)
        if payloadLength == 126 {
            guard data.count >= cursor + 2 else { throw DecodeError.incompleteHeader }
            payloadLength = (Int(bytes[cursor]) << 8) | Int(bytes[cursor + 1])
            cursor += 2
        } else if payloadLength == 127 {
            guard data.count >= cursor + 8 else { throw DecodeError.incompleteHeader }
            var length: UInt64 = 0
            for i in 0..<8 { length = (length << 8) | UInt64(bytes[cursor + i]) }
            cursor += 8
            // 63-bit cap per RFC; cap below at our buffer ceiling.
            if length > UInt64(Int.max) { throw DecodeError.payloadTooLarge }
            payloadLength = Int(length)
        }
        if payloadLength > maxPayloadSize { throw DecodeError.payloadTooLarge }
        // Mask key always follows for client frames.
        guard data.count >= cursor + 4 else { throw DecodeError.incompleteHeader }
        let maskKey: [UInt8] = Array(bytes[cursor..<(cursor + 4)])
        cursor += 4
        guard data.count >= cursor + payloadLength else { throw DecodeError.incompletePayload }
        var payload = [UInt8](repeating: 0, count: payloadLength)
        for i in 0..<payloadLength {
            payload[i] = bytes[cursor + i] ^ maskKey[i % 4]
        }
        cursor += payloadLength
        return (WebSocketFrame(fin: fin, opcode: opcode, payload: Data(payload)), cursor)
    }

    /// Encode an outbound frame. No mask (server→client). Caller picks the
    /// opcode — `text` for JSON, `ping` for keepalive, `close` for shutdown.
    static func encodeServerFrame(_ frame: WebSocketFrame) -> Data {
        var out = Data()
        var b0: UInt8 = frame.opcode.rawValue & 0x0F
        if frame.fin { b0 |= 0x80 }
        out.append(b0)
        let length = frame.payload.count
        if length < 126 {
            out.append(UInt8(length))
        } else if length <= 0xFFFF {
            out.append(126)
            out.append(UInt8((length >> 8) & 0xFF))
            out.append(UInt8(length & 0xFF))
        } else {
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((UInt64(length) >> shift) & 0xFF))
            }
        }
        out.append(frame.payload)
        return out
    }

    /// Build a `text` frame (the common case — JSON payloads).
    static func encodeText(_ text: String) -> Data {
        encodeServerFrame(WebSocketFrame(fin: true, opcode: .text, payload: Data(text.utf8)))
    }

    /// Build a `close` frame with the optional 2-byte status code prefix.
    static func encodeClose(code: WebSocketCloseCode, reason: String = "") -> Data {
        var payload = Data()
        let raw = code.rawValue
        payload.append(UInt8((raw >> 8) & 0xFF))
        payload.append(UInt8(raw & 0xFF))
        if !reason.isEmpty {
            payload.append(contentsOf: reason.utf8)
        }
        return encodeServerFrame(WebSocketFrame(fin: true, opcode: .close, payload: payload))
    }

    /// Build a `ping` frame with the optional payload bytes echoed back in
    /// the matching `pong`.
    static func encodePing(payload: Data = Data()) -> Data {
        encodeServerFrame(WebSocketFrame(fin: true, opcode: .ping, payload: payload))
    }

    /// Build a `pong` frame echoing a received ping's payload.
    static func encodePong(payload: Data = Data()) -> Data {
        encodeServerFrame(WebSocketFrame(fin: true, opcode: .pong, payload: payload))
    }
}

// MARK: - Session

#if os(macOS)

nonisolated private let webSocketLogger = Logger(subsystem: Logging.subsystem, category: "WebSocket")

/// Per-connection state for one open WebSocket. Lives on the main actor
/// alongside the rest of `RemoteServer`. The session owns its `NWConnection`
/// lifecycle once the HTTP upgrade has completed: the server hands it the
/// already-receiving connection and the session is responsible for cancel
/// on close.
@MainActor
final class WebSocketSession {

    /// Folder ids this session has subscribed to. Mutated only on main.
    /// Reads from the server's fan-out loop happen on main as well.
    private(set) var subscribedFolderIds: Set<String> = []

    /// Captured peer info for the connected-viewers list (#0092). The
    /// session is the source of truth for "this peer is connected over WS".
    private(set) var peer: PeerInfo

    /// Reference to the underlying transport.
    private let connection: NWConnection

    /// Frames queued while an earlier send was in flight. We always have at
    /// most one outstanding `connection.send`; on its completion we drain
    /// the next entry. Fixes interleaving when a reload broadcast lands
    /// while a ping is still being flushed.
    private var sendQueue: [Data] = []
    private var sendInFlight = false

    /// Receive-side accumulator. Network.framework hands us arbitrary
    /// chunks; we glue them together and pull frames off the head as they
    /// complete.
    private var receiveBuffer = Data()

    /// Pong-watchdog timer. Set whenever a ping is sent; cleared when the
    /// matching pong arrives. If it fires we close the session — the
    /// viewer (or NAT) has gone away.
    private var pingTask: Task<Void, Never>?
    private var pongWatchdog: Task<Void, Never>?

    /// Set when the session has emitted a `close` frame or scheduled
    /// `connection.cancel()`. Used to drop late writes silently.
    private(set) var isClosed = false

    /// Callbacks set by the owner (RemoteServer). All fire on the main
    /// actor.
    var onSubscribe: ((WebSocketSession, [String]) -> Void)?
    var onUnsubscribe: ((WebSocketSession, [String]) -> Void)?
    var onClose: ((WebSocketSession) -> Void)?

    /// Ping/pong intervals — RFC 6455 doesn't mandate values, the spec
    /// pulls them from #0100: 30 s ping, 10 s pong timeout.
    private let pingInterval: Duration
    private let pongTimeout: Duration

    init(
        connection: NWConnection,
        peer: PeerInfo,
        pingInterval: Duration = .seconds(30),
        pongTimeout: Duration = .seconds(10)
    ) {
        self.connection = connection
        self.peer = peer
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
    }

    // MARK: - Lifecycle

    /// Begin the receive loop and the keepalive ping. The server calls this
    /// after the 101 response has been flushed.
    func start() {
        scheduleReceive()
        startPingLoop()
    }

    /// Close the session cleanly. Sends a close frame with `code` and then
    /// cancels the connection. Idempotent.
    func close(code: WebSocketCloseCode, reason: String = "") {
        guard !isClosed else { return }
        isClosed = true
        pingTask?.cancel()
        pongWatchdog?.cancel()
        let payload = WebSocketFraming.encodeClose(code: code, reason: reason)
        // Queue the close frame and then cancel after it lands. We don't
        // wait for the peer's close echo — v1 doesn't need a clean
        // graceful close, and the cancel below also kills inbound reads.
        enqueue(payload)
        connection.cancel()
        onClose?(self)
    }

    // MARK: - Outbound

    /// Encode + queue a `RemoteEvent` for the client. No-op if closed.
    func send(_ event: RemoteEvent) {
        guard !isClosed else { return }
        // Test seam: when a recorder is attached, capture the event in
        // memory instead of writing to the connection. Lets the fan-out
        // tests verify which events landed without standing up a real
        // socket.
        if let recorder = _testRecorder {
            recorder(event)
            return
        }
        do {
            let data = try RemoteProtocol.encoder.encode(event)
            guard let text = String(data: data, encoding: .utf8) else { return }
            enqueue(WebSocketFraming.encodeText(text))
        } catch {
            webSocketLogger.warning("encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Direct text send (tests use this to bypass `RemoteEvent`).
    func sendText(_ text: String) {
        guard !isClosed else { return }
        enqueue(WebSocketFraming.encodeText(text))
    }

    private func enqueue(_ bytes: Data) {
        sendQueue.append(bytes)
        flushSendQueue()
    }

    private func flushSendQueue() {
        guard !sendInFlight, !sendQueue.isEmpty else { return }
        let next = sendQueue.removeFirst()
        sendInFlight = true
        connection.send(content: next, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.sendInFlight = false
                if let error {
                    webSocketLogger.warning("ws send failed: \(error.localizedDescription, privacy: .public)")
                    self.close(code: .internalError)
                    return
                }
                self.flushSendQueue()
            }
        })
    }

    // MARK: - Inbound

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                if let error {
                    webSocketLogger.warning("ws receive failed: \(error.localizedDescription, privacy: .public)")
                    self.close(code: .internalError)
                    return
                }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.drainReceiveBuffer()
                }
                if isComplete {
                    self.close(code: .normal)
                    return
                }
                if !self.isClosed {
                    self.scheduleReceive()
                }
            }
        }
    }

    private func drainReceiveBuffer() {
        while !receiveBuffer.isEmpty {
            do {
                let (frame, consumed) = try WebSocketFraming.decodeClientFrame(from: receiveBuffer)
                receiveBuffer.removeFirst(consumed)
                handle(frame: frame)
                if isClosed { return }
            } catch WebSocketFraming.DecodeError.incompleteHeader,
                    WebSocketFraming.DecodeError.incompletePayload {
                // Need more bytes; wait for the next chunk.
                return
            } catch WebSocketFraming.DecodeError.payloadTooLarge {
                close(code: .policyViolation, reason: "frame_too_large")
                return
            } catch {
                close(code: .protocolError)
                return
            }
        }
    }

    private func handle(frame: WebSocketFrame) {
        switch frame.opcode {
        case .text:
            handleTextFrame(frame)
        case .close:
            close(code: .normal)
        case .ping:
            enqueue(WebSocketFraming.encodePong(payload: frame.payload))
        case .pong:
            // Treat any pong as a fresh liveness signal.
            pongWatchdog?.cancel()
            pongWatchdog = nil
        case .binary:
            // v1 only handles JSON-on-text. A spec-conforming client never
            // sends binary on this endpoint.
            close(code: .unsupportedData)
        case .continuation:
            // We don't advertise fragment support; reject early.
            close(code: .protocolError)
        }
    }

    private func handleTextFrame(_ frame: WebSocketFrame) {
        guard let text = frame.textPayload else {
            close(code: .protocolError, reason: "invalid_utf8")
            return
        }
        let command: RemoteCommand
        do {
            command = try RemoteProtocol.decoder.decode(RemoteCommand.self, from: Data(text.utf8))
        } catch {
            // Bad JSON / wrong shape — surface and ignore, don't drop the
            // connection. The viewer may roll its own keepalive.
            webSocketLogger.warning("ws decode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        switch command.type {
        case .subscribe:
            let ids = command.folderIds ?? []
            subscribedFolderIds.formUnion(ids)
            onSubscribe?(self, ids)
        case .unsubscribe:
            let ids = command.folderIds ?? []
            subscribedFolderIds.subtract(ids)
            onUnsubscribe?(self, ids)
        case .ping:
            send(.pong)
        }
    }

    // MARK: - Keepalive

    private func startPingLoop() {
        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.pingInterval)
                } catch { return }
                if Task.isCancelled { return }
                await MainActor.run { self.sendPing() }
            }
        }
    }

    private func sendPing() {
        guard !isClosed else { return }
        enqueue(WebSocketFraming.encodePing())
        pongWatchdog?.cancel()
        pongWatchdog = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.pongTimeout)
            } catch { return }
            if Task.isCancelled { return }
            await MainActor.run {
                webSocketLogger.notice("ws pong timeout; closing session")
                self.close(code: .goingAway, reason: "pong_timeout")
            }
        }
    }

    // MARK: - Server-side mutation hooks

    /// Called by the server when a subscribed folder is removed from the
    /// shared list (`HostFolderStore.setShared(_, false)`). Drops the
    /// folder id and emits the `unsubscribed` event.
    func dropSubscription(folderId: String, reason: String) {
        guard subscribedFolderIds.remove(folderId) != nil else { return }
        send(.unsubscribed(folderId: folderId, reason: reason))
    }

    /// Update the connected-viewers display name once auth has classified
    /// the token. Mirrors the `RemoteServer` peer-info path used for REST.
    func updatePeer(tokenName: String?) {
        peer.tokenName = tokenName
    }

    // MARK: - Test seams

    /// Test-only: apply a `RemoteCommand` as if it had arrived as a text
    /// frame. Goes through the same mutation paths (`subscribedFolderIds`
    /// + `onSubscribe`/`onUnsubscribe` callbacks) so we exercise the real
    /// state machine without standing up a TCP connection.
    func _applyCommandForTest(_ command: RemoteCommand) {
        switch command.type {
        case .subscribe:
            let ids = command.folderIds ?? []
            subscribedFolderIds.formUnion(ids)
            onSubscribe?(self, ids)
        case .unsubscribe:
            let ids = command.folderIds ?? []
            subscribedFolderIds.subtract(ids)
            onUnsubscribe?(self, ids)
        case .ping:
            send(.pong)
        }
    }

    /// Test-only: record outbound events instead of writing them to the
    /// connection. Set this before exercising the session; nil means
    /// "use the real send queue" (production behavior).
    var _testRecorder: ((RemoteEvent) -> Void)?
}

#endif
