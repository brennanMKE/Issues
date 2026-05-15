import Testing
import Foundation
@testable import IssuesCore

#if os(macOS)

/// Tests for `RemoteHostIssueSource` (#0094). Injects a stub
/// `RemoteClientProtocol` so the suite never touches the network; the
/// integration round-trip is covered manually via the smoke CLI (#0087).
@MainActor
struct RemoteHostIssueSourceTests {

    // MARK: - Stub client

    final class StubClient: RemoteClientProtocol, @unchecked Sendable {
        var folder: FolderInfo
        var issues: [IssueMetadata]
        var details: [String: IssueDetail] = [:]
        var foldersList: [FolderInfo] = []
        var folderError: RemoteClientError?
        var foldersError: RemoteClientError?
        var issuesError: RemoteClientError?
        var detailError: RemoteClientError?
        private(set) var detailFetchCount: [String: Int] = [:]

        init(folder: FolderInfo, issues: [IssueMetadata]) {
            self.folder = folder
            self.issues = issues
            self.foldersList = [folder]
        }

        func fetchFolder(id: String) async throws -> FolderInfo {
            if let folderError { throw folderError }
            return folder
        }
        func fetchFolders() async throws -> [FolderInfo] {
            if let foldersError { throw foldersError }
            return foldersList
        }
        func fetchIssues(folderId: String) async throws -> [IssueMetadata] {
            if let issuesError { throw issuesError }
            return issues
        }
        func fetchIssueDetail(folderId: String, id: String) async throws -> IssueDetail {
            detailFetchCount[id, default: 0] += 1
            if let detailError { throw detailError }
            guard let detail = details[id] else { throw RemoteClientError.notFound }
            return detail
        }
        func fetchAttachmentData(folderId: String, issueId: String, name: String) async throws -> Data {
            throw RemoteClientError.notFound
        }
    }

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private static func folderInfo(id: String = "f1", name: String = "Demo") -> FolderInfo {
        FolderInfo(
            id: id,
            name: name,
            url: URL(string: "https://example.com/demo"),
            description: nil,
            parentPath: "/Users/x/Code/Demo",
            issueCount: 0,
            modifiedAt: fixedDate
        )
    }

    private static func metadata(
        id: String,
        title: String = "Issue",
        modules: [String] = ["Services", "State"],
        modifiedAt: Date = fixedDate
    ) -> IssueMetadata {
        IssueMetadata(
            id: id,
            title: title,
            status: "open",
            modules: modules,
            platform: "macOS",
            firstSeen: nil,
            closedAt: nil,
            hasAttachments: false,
            modifiedAt: modifiedAt
        )
    }

    private static func detail(id: String, body: String) -> IssueDetail {
        IssueDetail(
            metadata: metadata(id: id),
            body: body,
            attachments: []
        )
    }

    /// Drives `reload()` to completion. The source kicks off an async
    /// task; we need to await its termination before asserting on
    /// observable state. Polls `inFlightReloadTask == nil` is fragile;
    /// instead we yield until `loadError` or `issues.isEmpty == false`.
    private static func awaitReload(_ source: RemoteHostIssueSource) async {
        // The reload Task fires on the main actor; a short Task.yield
        // loop is enough to let it land before the assertions run.
        for _ in 0..<100 {
            if !source.issues.isEmpty || source.loadError != nil || source.folderInvalidated { return }
            await Task.yield()
        }
    }

    // MARK: - Happy path

    @Test func startPopulatesDisplayNameAndIssues() async {
        let stub = StubClient(
            folder: Self.folderInfo(name: "Bluesky"),
            issues: [Self.metadata(id: "0001"), Self.metadata(id: "0002")]
        )
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_x", folderId: "f1", client: stub)
        source.start()
        await Self.awaitReload(source)
        #expect(source.displayName == "Bluesky")
        #expect(source.issues.count == 2)
        #expect(source.issues.first?.module == "Services / State")
        #expect(source.loadError == nil)
        #expect(source.folderInvalidated == false)
    }

    // MARK: - Error mapping

    @Test func unauthorizedSurfacesTokenInvalidAndStopsLoading() async {
        let stub = StubClient(folder: Self.folderInfo(), issues: [])
        stub.folderError = .unauthorized
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_bad", folderId: "f1", client: stub)
        var collected: [RemoteIssueSourceEvent] = []
        let listener = Task {
            for await event in source.eventStream {
                collected.append(event)
                if event == .tokenInvalid { break }
            }
        }
        source.start()
        await listener.value
        #expect(collected.contains(.tokenInvalid))
        #expect(source.issues.isEmpty)
        #expect(source.loadError != nil)
    }

    @Test func folderNotFoundFlipsFolderInvalidatedAndYieldsEvent() async {
        let stub = StubClient(folder: Self.folderInfo(), issues: [])
        stub.folderError = .folderNotFound
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_x", folderId: "f1", client: stub)
        var collected: [RemoteIssueSourceEvent] = []
        let listener = Task {
            for await event in source.eventStream {
                collected.append(event)
                if event == .folderUnavailable { break }
            }
        }
        source.start()
        await listener.value
        #expect(collected.contains(.folderUnavailable))
        #expect(source.folderInvalidated == true)
    }

    @Test func transportFailureYieldsDisconnected() async {
        let stub = StubClient(folder: Self.folderInfo(), issues: [])
        stub.folderError = .transport("network down")
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_x", folderId: "f1", client: stub)
        var collected: [RemoteIssueSourceEvent] = []
        let listener = Task {
            for await event in source.eventStream {
                collected.append(event)
                if event == .disconnected { break }
            }
        }
        source.start()
        await listener.value
        #expect(collected.contains(.disconnected))
    }

    // MARK: - Body cache

    @Test func fetchBodyHitsTheNetworkOnceThenCaches() async throws {
        let stub = StubClient(
            folder: Self.folderInfo(),
            issues: [Self.metadata(id: "0001")]
        )
        stub.details["0001"] = Self.detail(id: "0001", body: "## Description\n\nHello.")
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_x", folderId: "f1", client: stub)
        source.start()
        await Self.awaitReload(source)

        let firstBody = try await source.fetchBody(for: "0001")
        let secondBody = try await source.fetchBody(for: "0001")
        #expect(firstBody == "## Description\n\nHello.")
        #expect(secondBody == firstBody)
        #expect(stub.detailFetchCount["0001"] == 1)
        #expect(source.hasCachedBody(for: "0001"))
        #expect(source.issues.first?.description == "## Description\n\nHello.")
    }

    @Test func reloadInvalidatesCacheWhenMtimeMoves() async throws {
        let firstMtime = Date(timeIntervalSince1970: 1_715_000_000)
        let secondMtime = Date(timeIntervalSince1970: 1_715_010_000)
        let stub = StubClient(
            folder: Self.folderInfo(),
            issues: [Self.metadata(id: "0001", modifiedAt: firstMtime)]
        )
        stub.details["0001"] = Self.detail(id: "0001", body: "v1")
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_x", folderId: "f1", client: stub)
        source.start()
        await Self.awaitReload(source)
        _ = try await source.fetchBody(for: "0001")
        #expect(stub.detailFetchCount["0001"] == 1)

        // Simulate the host's mtime moving for issue 0001.
        stub.issues = [Self.metadata(id: "0001", modifiedAt: secondMtime)]
        source.reload()
        // Drain reload.
        for _ in 0..<100 {
            if source.issues.first?.modifiedAt == secondMtime { break }
            await Task.yield()
        }
        #expect(source.hasCachedBody(for: "0001") == false)
    }

    @Test func reloadDropsCachedBodyForIssuesThatVanish() async throws {
        let stub = StubClient(
            folder: Self.folderInfo(),
            issues: [Self.metadata(id: "0001"), Self.metadata(id: "0002")]
        )
        stub.details["0001"] = Self.detail(id: "0001", body: "one")
        let source = RemoteHostIssueSource(host: "10.0.0.1", port: 5000, token: "iat_x", folderId: "f1", client: stub)
        source.start()
        await Self.awaitReload(source)
        _ = try await source.fetchBody(for: "0001")
        #expect(source.hasCachedBody(for: "0001"))

        stub.issues = [Self.metadata(id: "0002")]
        source.reload()
        for _ in 0..<100 {
            if source.issues.count == 1 { break }
            await Task.yield()
        }
        #expect(source.hasCachedBody(for: "0001") == false)
    }

    // MARK: - Identity passthroughs

    @Test func folderIdHashesRemoteIdentity() {
        let a = RemoteHostIssueSource(host: "h", port: 1, token: "t", folderId: "f")
        let b = RemoteHostIssueSource(host: "h", port: 1, token: "t", folderId: "f")
        let c = RemoteHostIssueSource(host: "h", port: 1, token: "t", folderId: "g")
        #expect(a.bookmarkData == b.bookmarkData)
        #expect(a.bookmarkData != c.bookmarkData)
    }
}

#endif
