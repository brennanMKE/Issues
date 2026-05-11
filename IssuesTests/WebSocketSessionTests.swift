import Testing
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for #0100 / #0101: the RFC 6455 framing helpers, the per-session
/// subscription state, and the server's fan-out map. The framing tests are
/// pure and don't stand up any network. The session/fanout tests use the
/// public hooks on `WebSocketSession` and a small in-process driver instead
/// of `NWConnection` so they're deterministic.
struct WebSocketSessionTests {

    // MARK: - Handshake

    @Test func acceptValueMatchesRFC6455Example() {
        // RFC 6455 §1.3 worked example: the canonical client key
        // `dGhlIHNhbXBsZSBub25jZQ==` MUST hash to
        // `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`.
        let accept = WebSocketHandshake.acceptValue(forKey: "dGhlIHNhbXBsZSBub25jZQ==")
        #expect(accept == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func upgradeDetectionAcceptsStandardHeaders() {
        let headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "Upgrade",
            "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
            "Sec-WebSocket-Version": "13"
        ]
        #expect(WebSocketHandshake.isUpgradeRequest(headers: headers))
    }

    @Test func upgradeDetectionAllowsKeepAliveStyleConnectionHeader() {
        // Some clients send "keep-alive, Upgrade" — the spec says
        // `Connection` MUST contain `Upgrade`, case-insensitive.
        let headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "keep-alive, Upgrade",
            "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
            "Sec-WebSocket-Version": "13"
        ]
        #expect(WebSocketHandshake.isUpgradeRequest(headers: headers))
    }

    @Test func upgradeDetectionRejectsMissingKey() {
        let headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "Upgrade",
            "Sec-WebSocket-Version": "13"
        ]
        #expect(!WebSocketHandshake.isUpgradeRequest(headers: headers))
    }

    @Test func upgradeDetectionRejectsWrongVersion() {
        let headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "Upgrade",
            "Sec-WebSocket-Key": "abc",
            "Sec-WebSocket-Version": "8"
        ]
        #expect(!WebSocketHandshake.isUpgradeRequest(headers: headers))
    }

    @Test func upgradeResponseEmits101AndAcceptHeader() {
        let bytes = WebSocketHandshake.upgradeResponse(clientKey: "dGhlIHNhbXBsZSBub25jZQ==")
        let text = String(data: bytes, encoding: .utf8) ?? ""
        #expect(text.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
        #expect(text.contains("\r\nUpgrade: websocket\r\n"))
        #expect(text.contains("\r\nConnection: Upgrade\r\n"))
        #expect(text.contains("\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    // MARK: - Frame builder (server → client)

    @Test func encodeServerTextFrameMatchesRFCShape() {
        // RFC 6455 §5.7 single-frame unmasked "Hello":
        // 0x81 0x05 0x48 0x65 0x6c 0x6c 0x6f.
        let bytes = WebSocketFraming.encodeText("Hello")
        #expect([UInt8](bytes) == [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f])
    }

    @Test func encodeServerCloseFrameIncludesStatusCode() {
        let bytes = WebSocketFraming.encodeClose(code: .tokenRevoked)
        let raw = [UInt8](bytes)
        // 0x88 = FIN + opcode 0x8 (close). 0x02 = payload length 2.
        #expect(raw[0] == 0x88)
        #expect(raw[1] == 0x02)
        // 4001 = 0x0FA1 — big-endian on the wire.
        #expect(raw[2] == 0x0F)
        #expect(raw[3] == 0xA1)
    }

    @Test func encodeServerPingHasOpcode9() {
        let bytes = WebSocketFraming.encodePing()
        let raw = [UInt8](bytes)
        #expect(raw[0] == 0x89)
        #expect(raw[1] == 0x00)
    }

    @Test func encodeServerFrameExtendedLength16() {
        // Boundary case: 126-byte payload encodes the length in a 16-bit
        // big-endian word after the second header byte.
        let payload = Data(repeating: 0x41, count: 126)
        let frame = WebSocketFrame(fin: true, opcode: .text, payload: payload)
        let bytes = [UInt8](WebSocketFraming.encodeServerFrame(frame))
        #expect(bytes[0] == 0x81)
        #expect(bytes[1] == 126)
        #expect(bytes[2] == 0x00)
        #expect(bytes[3] == 0x7E)
        #expect(bytes.count == 4 + 126)
    }

    // MARK: - Frame parser (client → server)

    @Test func decodeMaskedTextFrameRoundTrip() throws {
        // Client-style "Hello" with mask 0x37 0xfa 0x21 0x3d (RFC 6455
        // §5.7 example).
        let raw: [UInt8] = [
            0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d,
            0x7f, 0x9f, 0x4d, 0x51, 0x58
        ]
        let (frame, consumed) = try WebSocketFraming.decodeClientFrame(from: Data(raw))
        #expect(frame.fin == true)
        #expect(frame.opcode == .text)
        #expect(frame.textPayload == "Hello")
        #expect(consumed == raw.count)
    }

    @Test func decodeMaskedPingFrame() throws {
        // 0x89 0x80 + 4-byte mask + 0-byte payload. Empty ping.
        let raw: [UInt8] = [0x89, 0x80, 0x12, 0x34, 0x56, 0x78]
        let (frame, consumed) = try WebSocketFraming.decodeClientFrame(from: Data(raw))
        #expect(frame.opcode == .ping)
        #expect(frame.payload.isEmpty)
        #expect(consumed == raw.count)
    }

    @Test func decodeMaskedPongFrame() throws {
        // 0x8A masked, payload "ab" XOR'd with the mask.
        // Plaintext 'a','b' = 0x61 0x62. Mask = 0x10 0x20 0x30 0x40.
        // Wire = 0x71 0x42.
        let raw: [UInt8] = [0x8A, 0x82, 0x10, 0x20, 0x30, 0x40, 0x71, 0x42]
        let (frame, _) = try WebSocketFraming.decodeClientFrame(from: Data(raw))
        #expect(frame.opcode == .pong)
        #expect(frame.payload == Data([0x61, 0x62]))
    }

    @Test func decodeMaskedCloseFrame() throws {
        // Close with 2-byte status code 1000.
        // Plaintext = 0x03 0xE8. Mask = 0xAA 0xBB 0xCC 0xDD.
        // Wire = 0xA9 0x53.
        let raw: [UInt8] = [0x88, 0x82, 0xAA, 0xBB, 0xCC, 0xDD, 0xA9, 0x53]
        let (frame, _) = try WebSocketFraming.decodeClientFrame(from: Data(raw))
        #expect(frame.opcode == .close)
        #expect(frame.payload == Data([0x03, 0xE8]))
    }

    @Test func decodeRejectsUnmaskedClientFrame() {
        // Same "Hello" payload but no mask bit set — RFC requires masking
        // from client→server, so the parser MUST reject it.
        let raw: [UInt8] = [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]
        do {
            _ = try WebSocketFraming.decodeClientFrame(from: Data(raw))
            Issue.record("expected clientFrameNotMasked")
        } catch let error as WebSocketFraming.DecodeError {
            #expect(error == .clientFrameNotMasked)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func decodeReportsIncompleteHeader() {
        let raw: [UInt8] = [0x81]
        do {
            _ = try WebSocketFraming.decodeClientFrame(from: Data(raw))
            Issue.record("expected incompleteHeader")
        } catch let error as WebSocketFraming.DecodeError {
            #expect(error == .incompleteHeader)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func decodeReportsIncompletePayload() {
        // Frame says 5-byte payload but only delivers 2.
        let raw: [UInt8] = [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f]
        do {
            _ = try WebSocketFraming.decodeClientFrame(from: Data(raw))
            Issue.record("expected incompletePayload")
        } catch let error as WebSocketFraming.DecodeError {
            #expect(error == .incompletePayload)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - RemoteEvent wire shape

    @Test func remoteEventEncodesFlatJSONWithSkippedNils() throws {
        let event = RemoteEvent.reload(folderId: "abc")
        let body = try RemoteProtocol.encoder.encode(event)
        let json = try #require(String(data: body, encoding: .utf8))
        // No null fields — encodeIfPresent should skip them.
        #expect(!json.contains("null"))
        #expect(json.contains("\"type\":\"reload\""))
        #expect(json.contains("\"folderId\":\"abc\""))
    }

    @Test func remoteEventHelloIncludesVersionAndDisplayName() throws {
        let event = RemoteEvent.hello(displayName: "Brennan's MacBook Air")
        let body = try RemoteProtocol.encoder.encode(event)
        let decoded = try RemoteProtocol.decoder.decode(RemoteEvent.self, from: body)
        #expect(decoded.type == .hello)
        #expect(decoded.displayName == "Brennan's MacBook Air")
        #expect(decoded.version == RemoteProtocol.version)
        #expect(decoded.folderId == nil)
    }

    @Test func remoteEventUnsubscribedCarriesReason() throws {
        let event = RemoteEvent.unsubscribed(folderId: "abc", reason: "host_unshared")
        let body = try RemoteProtocol.encoder.encode(event)
        let json = String(data: body, encoding: .utf8) ?? ""
        #expect(json.contains("\"reason\":\"host_unshared\""))
    }

    @Test func remoteCommandDecodesSubscribe() throws {
        let raw = #"{"type":"subscribe","folderIds":["a3f1","97c0"]}"#
        let command = try RemoteProtocol.decoder.decode(RemoteCommand.self, from: Data(raw.utf8))
        #expect(command.type == .subscribe)
        #expect(command.folderIds == ["a3f1", "97c0"])
    }

    @Test func remoteCommandDecodesPingWithoutFolderIds() throws {
        let raw = #"{"type":"ping"}"#
        let command = try RemoteProtocol.decoder.decode(RemoteCommand.self, from: Data(raw.utf8))
        #expect(command.type == .ping)
        #expect(command.folderIds == nil)
    }

    // MARK: - Close codes

    @Test func tokenRevokedCloseCodeIs4001() {
        #expect(WebSocketCloseCode.tokenRevoked.rawValue == 4001)
    }
}

#endif
