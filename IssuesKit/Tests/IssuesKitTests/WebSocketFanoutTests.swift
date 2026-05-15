import Testing
import Foundation
@testable import IssuesCore

#if os(macOS)
import Network

/// Tests for #0101 fanout behavior: subscribe/unsubscribe state on a
/// `WebSocketSession` and the routing each event takes through the
/// in-memory subscriber map. The sessions here are constructed against a
/// `NWConnection` that is never `start()`-ed, so no real network I/O
/// occurs; the test recorder seam captures outbound events instead of
/// writing wire bytes.
@MainActor
struct WebSocketFanoutTests {

    // MARK: - Fake connection helper

    /// Creates an `NWConnection` to an unreachable endpoint and returns it
    /// without ever calling `start(queue:)`. Network.framework happily
    /// constructs the object lazily; we only need it as an opaque handle
    /// so `WebSocketSession.init` can accept it.
    private static func makeDormantConnection() -> NWConnection {
        // Port 1 / 127.0.0.1 — unused; the connection sits idle since we
        // never start it.
        NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: 1)!,
            using: .tcp
        )
    }

    private static func makeSession() -> WebSocketSession {
        let peer = PeerInfo(remoteAddress: "127.0.0.1:0", tokenName: nil, connectedAt: Date())
        let session = WebSocketSession(connection: makeDormantConnection(), peer: peer)
        return session
    }

    // MARK: - Subscription state

    @Test func subscribeIsAdditive() {
        let session = Self.makeSession()
        session._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["a"]))
        session._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["b", "c"]))
        #expect(session.subscribedFolderIds == ["a", "b", "c"])
    }

    @Test func unsubscribeRemovesSpecifiedIdsOnly() {
        let session = Self.makeSession()
        session._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["a", "b", "c"]))
        session._applyCommandForTest(RemoteCommand(type: .unsubscribe, folderIds: ["b"]))
        #expect(session.subscribedFolderIds == ["a", "c"])
    }

    @Test func subscribeUnsubscribeSubscribeCycle() {
        let session = Self.makeSession()
        session._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["a"]))
        session._applyCommandForTest(RemoteCommand(type: .unsubscribe, folderIds: ["a"]))
        session._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["a"]))
        #expect(session.subscribedFolderIds == ["a"])
    }

    @Test func dropSubscriptionEmitsUnsubscribedEventAndRemovesId() {
        let session = Self.makeSession()
        var captured: [RemoteEvent] = []
        session._testRecorder = { captured.append($0) }
        session._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["a", "b"]))
        session.dropSubscription(folderId: "a", reason: "host_unshared")
        #expect(session.subscribedFolderIds == ["b"])
        #expect(captured.contains { $0.type == .unsubscribed && $0.folderId == "a" && $0.reason == "host_unshared" })
    }

    @Test func dropSubscriptionNoOpWhenNotSubscribed() {
        let session = Self.makeSession()
        var captured: [RemoteEvent] = []
        session._testRecorder = { captured.append($0) }
        session.dropSubscription(folderId: "absent", reason: "host_unshared")
        #expect(captured.isEmpty)
    }

    // MARK: - Fan-out routing (manual)

    /// Mirrors the server-side fan-out logic. Verifies the documented
    /// behavior that exactly the subscribed session receives a folder's
    /// reload event.
    @Test func fanoutOnlyDeliversToSubscribers() {
        let alpha = Self.makeSession()
        let beta = Self.makeSession()
        var alphaEvents: [RemoteEvent] = []
        var betaEvents: [RemoteEvent] = []
        alpha._testRecorder = { alphaEvents.append($0) }
        beta._testRecorder = { betaEvents.append($0) }

        // Subscribe alpha to A, beta to B.
        alpha._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["A"]))
        beta._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["B"]))

        // Drive the same routing the server does: only sessions with the
        // folder in their subscribed set receive the event.
        let event = RemoteEvent.reload(folderId: "A")
        for session in [alpha, beta] where session.subscribedFolderIds.contains("A") {
            session.send(event)
        }
        #expect(alphaEvents.count == 1)
        #expect(alphaEvents.first?.type == .reload)
        #expect(alphaEvents.first?.folderId == "A")
        #expect(betaEvents.isEmpty)
    }

    @Test func multipleSubscribersToSameFolderBothReceiveEvent() {
        let one = Self.makeSession()
        let two = Self.makeSession()
        var oneEvents: [RemoteEvent] = []
        var twoEvents: [RemoteEvent] = []
        one._testRecorder = { oneEvents.append($0) }
        two._testRecorder = { twoEvents.append($0) }

        one._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["shared"]))
        two._applyCommandForTest(RemoteCommand(type: .subscribe, folderIds: ["shared"]))

        let event = RemoteEvent.reload(folderId: "shared")
        for session in [one, two] where session.subscribedFolderIds.contains("shared") {
            session.send(event)
        }
        #expect(oneEvents.count == 1)
        #expect(twoEvents.count == 1)
    }
}

#endif
