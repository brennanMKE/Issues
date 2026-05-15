import Testing
import IssuesCore
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for #0079: HTTP parser, route matching with placeholder
/// segments, auth middleware, and response shapes. The `NWListener`
/// itself is exercised manually via `curl` per the issue's verification
/// steps; the unit tests focus on the load-bearing pure-function layer.
struct RemoteServerTests {

    private static func uniqueService() -> String {
        "co.sstools.Issues.RemoteAccess.HostTokens.Test.\(UUID().uuidString)"
    }

    // MARK: - HTTPRequestParser

    @Test func parserAcceptsMinimalGet() throws {
        let raw = "GET /v1/host HTTP/1.1\r\nHost: 192.168.1.10:9000\r\n\r\n"
        let request = try HTTPRequestParser.parse(Data(raw.utf8))
        #expect(request.method == "GET")
        #expect(request.path == "/v1/host")
        #expect(request.headers["Host"] == "192.168.1.10:9000")
    }

    @Test func parserStripsQueryFromPath() throws {
        let raw = "GET /v1/folders/abc/issues?limit=5 HTTP/1.1\r\nHost: x\r\n\r\n"
        let request = try HTTPRequestParser.parse(Data(raw.utf8))
        #expect(request.path == "/v1/folders/abc/issues")
    }

    @Test func parserRejectsNonGet() {
        let raw = "POST /v1/host HTTP/1.1\r\nHost: x\r\n\r\n"
        do {
            _ = try HTTPRequestParser.parse(Data(raw.utf8))
            Issue.record("expected unsupportedMethod")
        } catch let error as HTTPRequestParser.ParseError {
            #expect(error == .unsupportedMethod)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func parserRejectsBodyOnGet() {
        let raw = "GET /v1/host HTTP/1.1\r\nHost: x\r\n\r\nillegal-body"
        do {
            _ = try HTTPRequestParser.parse(Data(raw.utf8))
            Issue.record("expected bodyOnGet")
        } catch let error as HTTPRequestParser.ParseError {
            #expect(error == .bodyOnGet)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func parserRejectsMissingHost() {
        let raw = "GET /v1/host HTTP/1.1\r\n\r\n"
        do {
            _ = try HTTPRequestParser.parse(Data(raw.utf8))
            Issue.record("expected missingHost")
        } catch let error as HTTPRequestParser.ParseError {
            #expect(error == .missingHost)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func parserHeadersAreCaseInsensitiveForAuth() throws {
        let raw = "GET /v1/host HTTP/1.1\r\nHost: x\r\nauthorization: Bearer iat_abc\r\n\r\n"
        let request = try HTTPRequestParser.parse(Data(raw.utf8))
        #expect(request.authorizationHeader == "Bearer iat_abc")
    }

    // MARK: - RouteTable

    @Test func routeTableMatchesLiteralPath() {
        var table = RouteTable()
        table.routes.append(Route(method: "GET", pathPattern: "/v1/host", handler: { _, _ in .ok(payload: [:]) }))
        let result = table.match(method: "GET", path: "/v1/host")
        #expect(result != nil)
        #expect(result?.1.isEmpty == true)
    }

    @Test func routeTableCapturesPlaceholders() {
        var table = RouteTable()
        table.routes.append(Route(
            method: "GET",
            pathPattern: "/v1/folders/{folderId}/issues/{id}",
            handler: { _, _ in .ok(payload: [:]) }
        ))
        let result = table.match(method: "GET", path: "/v1/folders/a3f1e0c082b41d77/issues/0001")
        let captures = try? #require(result?.1)
        #expect(captures?["folderId"] == "a3f1e0c082b41d77")
        #expect(captures?["id"] == "0001")
    }

    @Test func routeTableReturnsNilOnMismatch() {
        var table = RouteTable()
        table.routes.append(Route(method: "GET", pathPattern: "/v1/host", handler: { _, _ in .ok(payload: [:]) }))
        #expect(table.match(method: "GET", path: "/v1/folders") == nil)
        #expect(table.match(method: "GET", path: "/v1/host/extra") == nil)
    }

    @Test func routeTableMethodIsCaseInsensitive() {
        var table = RouteTable()
        table.routes.append(Route(method: "GET", pathPattern: "/v1/host", handler: { _, _ in .ok(payload: [:]) }))
        #expect(table.match(method: "get", path: "/v1/host") != nil)
    }

    // MARK: - AuthMiddleware (token extraction)

    @Test func extractBearerHandlesCommonShapes() {
        #expect(AuthMiddleware.extractBearer("Bearer iat_abc") == "iat_abc")
        #expect(AuthMiddleware.extractBearer("bearer iat_xyz") == "iat_xyz")
        #expect(AuthMiddleware.extractBearer("BEARER iat_zzz") == "iat_zzz")
        #expect(AuthMiddleware.extractBearer("Bearer  iat_padded ") == "iat_padded")
        #expect(AuthMiddleware.extractBearer("Basic dXNlcg==") == nil)
        #expect(AuthMiddleware.extractBearer("Bearer ") == nil)
        #expect(AuthMiddleware.extractBearer(nil) == nil)
    }

    // MARK: - AuthMiddleware (full classification)

    @Test func authMissingHeaderClassifiesAsMissing() {
        let outcome = AuthMiddleware.authenticate(authorizationHeader: nil, service: Self.uniqueService())
        #expect(outcome == .missingHeader)
        #expect(AuthMiddleware.failureResponse(for: outcome)?.status == 401)
    }

    @Test func authMalformedHeaderClassifiesAsMalformed() {
        let outcome = AuthMiddleware.authenticate(authorizationHeader: "Basic abcd", service: Self.uniqueService())
        #expect(outcome == .malformedHeader)
    }

    @Test func authUnknownTokenClassifiesAsInvalid() {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }
        let outcome = AuthMiddleware.authenticate(
            authorizationHeader: "Bearer iat_definitely-not-real",
            service: service
        )
        #expect(outcome == .invalidToken)
        let response = AuthMiddleware.failureResponse(for: outcome)
        let body = try? JSONSerialization.jsonObject(with: response?.body ?? Data()) as? [String: Any]
        #expect(body?["error"] as? String == "invalid_token")
    }

    @Test func authExpiredTokenClassifiesAsExpired() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }
        let (plaintext, _) = try AccessToken.generate(
            name: "expired",
            expiresAt: Date(timeIntervalSinceNow: -60),
            service: service
        )
        let outcome = AuthMiddleware.authenticate(authorizationHeader: "Bearer \(plaintext)", service: service)
        #expect(outcome == .expiredToken)
    }

    @Test func authValidTokenReturnsRecord() throws {
        let service = Self.uniqueService()
        defer { try? AccessToken.deleteAll(service: service) }
        let (plaintext, record) = try AccessToken.generate(name: "good", expiresAt: nil, service: service)
        let outcome = AuthMiddleware.authenticate(authorizationHeader: "Bearer \(plaintext)", service: service)
        if case .ok(let validated) = outcome {
            #expect(validated == record)
        } else {
            Issue.record("expected .ok, got \(outcome)")
        }
        #expect(AuthMiddleware.failureResponse(for: outcome) == nil)
    }

    // MARK: - HTTPResponse

    @Test func responseSerializationIncludesContentLengthAndConnectionClose() {
        let response = HTTPResponse.ok(payload: ["ok": true])
        let serialized = response.serialized()
        let text = String(data: serialized, encoding: .utf8) ?? ""
        #expect(text.contains("HTTP/1.1 200 OK"))
        #expect(text.contains("Content-Length: \(response.body.count)"))
        #expect(text.contains("Connection: close"))
        #expect(text.hasSuffix("\(String(data: response.body, encoding: .utf8) ?? "")"))
    }

    @Test func unauthorizedResponseHasJsonError() throws {
        let response = HTTPResponse.unauthorized(reason: "missing_token")
        #expect(response.status == 401)
        let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        #expect(payload?["error"] as? String == "missing_token")
    }
}

#endif
