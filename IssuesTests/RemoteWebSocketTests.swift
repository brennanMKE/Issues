import Testing
import IssuesCore
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for `RemoteWebSocket` (#0102) — the deterministic, no-network
/// surface: URL construction, backoff math, jitter bounds. The live
/// reconnect path is exercised manually per the issue's verification
/// section (the test rig requires a live host).
@MainActor
struct RemoteWebSocketTests {

    private static func make(
        schedule: [TimeInterval] = [1, 2, 4, 8, 16],
        cap: TimeInterval = 30,
        jitter: Double = 0
    ) -> RemoteWebSocket {
        RemoteWebSocket(
            host: "10.0.0.1",
            port: 50000,
            token: "iat_test",
            folderId: "f",
            pingInterval: 60,
            pongTimeout: 5,
            backoffSchedule: schedule,
            backoffCap: cap,
            jitterFraction: jitter
        )
    }

    // MARK: - URL

    @Test func urlBuildsForIPv4() {
        let url = try? #require(RemoteWebSocket.url(host: "192.168.1.42", port: 51823))
        #expect(url?.absoluteString == "wss://192.168.1.42:51823/v1/events")
    }

    @Test func urlBuildsForHostname() {
        let url = RemoteWebSocket.url(host: "my-mac.local", port: 9000)
        #expect(url?.absoluteString == "wss://my-mac.local:9000/v1/events")
    }

    @Test func urlBracketsIPv6Literal() {
        let url = RemoteWebSocket.url(host: "fe80::abcd", port: 5000)
        #expect(url?.absoluteString == "wss://[fe80::abcd]:5000/v1/events")
    }

    @Test func urlReturnsNilForEmptyHost() {
        #expect(RemoteWebSocket.url(host: "", port: 1) == nil)
        #expect(RemoteWebSocket.url(host: "   ", port: 1) == nil)
    }

    @Test func urlAcceptsExplicitWsSchemeForLegacy() {
        let url = RemoteWebSocket.url(host: "10.0.0.1", port: 5000, scheme: "ws")
        #expect(url?.absoluteString == "ws://10.0.0.1:5000/v1/events")
    }

    // MARK: - Backoff schedule

    @Test func backoffFollowsScheduleWithoutJitter() {
        let ws = Self.make(jitter: 0)
        #expect(abs(ws.nextBackoffDelay(forAttempt: 0) - 1.0) < 0.001)
        #expect(abs(ws.nextBackoffDelay(forAttempt: 1) - 2.0) < 0.001)
        #expect(abs(ws.nextBackoffDelay(forAttempt: 2) - 4.0) < 0.001)
        #expect(abs(ws.nextBackoffDelay(forAttempt: 3) - 8.0) < 0.001)
        #expect(abs(ws.nextBackoffDelay(forAttempt: 4) - 16.0) < 0.001)
        // Indices past the end of the schedule clamp to the last entry.
        #expect(abs(ws.nextBackoffDelay(forAttempt: 10) - 16.0) < 0.001)
    }

    @Test func backoffClampsToCap() {
        let ws = Self.make(schedule: [1, 2, 4, 8, 100], cap: 30, jitter: 0)
        #expect(abs(ws.nextBackoffDelay(forAttempt: 4) - 30.0) < 0.001)
    }

    @Test func backoffJitterStaysWithinBounds() {
        let ws = Self.make(jitter: 0.25)
        for _ in 0..<50 {
            let delay = ws.nextBackoffDelay(forAttempt: 4)
            // 16 ± 25% = [12, 20]
            #expect(delay >= 12.0 - 0.001)
            #expect(delay <= 20.0 + 0.001)
        }
    }

    @Test func backoffNeverGoesBelowFloor() {
        let ws = Self.make(schedule: [0.01], jitter: 0.99)
        for _ in 0..<50 {
            #expect(ws.nextBackoffDelay(forAttempt: 0) >= 0.1)
        }
    }
}

#endif
