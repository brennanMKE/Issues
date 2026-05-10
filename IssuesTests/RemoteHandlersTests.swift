import Testing
import Foundation
@testable import Issues

#if os(macOS)

/// Tests for #0080: REST handlers, wire-type encoding round-trips, and
/// the markdown body extractor. All handler tests use a stub
/// `MultiFolderStore` so the host doesn't have to be running and there's
/// no real Keychain/network involvement.
struct RemoteHandlersTests {

    // MARK: - Stub store

    final class StubStore: MultiFolderStore {
        var hostDisplayName: String = "Stub Host"
        var folders: [HostedFolder] = []

        func currentlyHostedFolders() -> [HostedFolder] { folders }

        func currentlyHostedFolder(forId id: String) -> HostedFolder? {
            folders.first { $0.id == id }
        }
    }

    private static func makeIssue(
        id: String,
        title: String = "Test issue",
        statusRaw: String = "open",
        module: String = "Services / State",
        platform: String = "macOS",
        modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        fileURL: URL = URL(fileURLWithPath: "/tmp/stub.md"),
        hasAttachments: Bool = false
    ) -> Issues.Issue {
        Issues.Issue(
            id: id,
            title: title,
            status: IssueStatus(raw: statusRaw),
            statusRaw: statusRaw,
            module: module,
            platform: platform,
            firstSeen: nil,
            firstSeenRaw: "",
            closed: nil,
            closedRaw: "",
            description: "",
            fileURL: fileURL,
            modifiedAt: modifiedAt,
            hasAttachments: hasAttachments
        )
    }

    private static func makeFolder(
        id: String = "a3f1e0c082b41d77",
        displayName: String = "MyRepo",
        url: URL = URL(fileURLWithPath: "/Users/x/Code/MyRepo/issues"),
        project: ProjectMetadata? = nil,
        issues: [Issues.Issue] = []
    ) -> HostedFolder {
        HostedFolder(
            id: id,
            folderURL: url,
            displayName: displayName,
            projectMetadata: project,
            issues: issues,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - /v1/host

    @Test func hostReturnsExpectedShape() throws {
        let store = StubStore()
        store.hostDisplayName = "Brennan's MacBook Air"
        store.folders = [Self.makeFolder(), Self.makeFolder(id: "ffffffffffffffff", displayName: "Other")]

        let response = try RemoteHandlers.host(store: store)
        #expect(response.status == 200)
        let info = try RemoteProtocol.decoder.decode(HostInfo.self, from: response.body)
        #expect(info.displayName == "Brennan's MacBook Air")
        #expect(info.version == 1)
        #expect(info.folderCount == 2)
    }

    // MARK: - /v1/folders

    @Test func foldersListReturnsAllHostedFolders() throws {
        let store = StubStore()
        store.folders = [
            Self.makeFolder(
                id: "aaaaaaaaaaaaaaaa",
                displayName: "Issues.app",
                url: URL(fileURLWithPath: "/Users/x/Code/Issues/project-issues"),
                project: ProjectMetadata(name: "Issues.app", url: URL(string: "https://github.com/brennanMKE/Issues")),
                issues: [Self.makeIssue(id: "0001"), Self.makeIssue(id: "0002")]
            ),
            Self.makeFolder(id: "bbbbbbbbbbbbbbbb", displayName: "scratch")
        ]
        let response = try RemoteHandlers.folders(store: store)
        #expect(response.status == 200)
        let infos = try RemoteProtocol.decoder.decode([FolderInfo].self, from: response.body)
        #expect(infos.count == 2)
        #expect(infos[0].id == "aaaaaaaaaaaaaaaa")
        #expect(infos[0].name == "Issues.app")
        #expect(infos[0].repository == URL(string: "https://github.com/brennanMKE/Issues"))
        #expect(infos[0].issueCount == 2)
        #expect(infos[0].parentPath == "/Users/x/Code/Issues")
    }

    // MARK: - /v1/folders/{folderId}

    @Test func folderByIdReturnsSingleFolder() throws {
        let store = StubStore()
        store.folders = [Self.makeFolder(id: "cccccccccccccccc")]
        let response = try RemoteHandlers.folder(store: store, captures: ["folderId": "cccccccccccccccc"])
        #expect(response.status == 200)
        let info = try RemoteProtocol.decoder.decode(FolderInfo.self, from: response.body)
        #expect(info.id == "cccccccccccccccc")
    }

    @Test func folderByIdUnknownReturns404() throws {
        let store = StubStore()
        let response = try RemoteHandlers.folder(store: store, captures: ["folderId": "ffffffffffffffff"])
        #expect(response.status == 404)
    }

    // MARK: - /v1/folders/{folderId}/issues

    @Test func issuesListReturnsMetadataForEveryIssue() throws {
        let store = StubStore()
        store.folders = [
            Self.makeFolder(
                id: "dddddddddddddddd",
                issues: [
                    Self.makeIssue(id: "0001", title: "First", statusRaw: "open", module: "Services / State"),
                    Self.makeIssue(id: "0002", title: "Second", statusRaw: "in-progress", module: "Views", platform: "All")
                ]
            )
        ]
        let response = try RemoteHandlers.issues(store: store, captures: ["folderId": "dddddddddddddddd"])
        #expect(response.status == 200)
        let metas = try RemoteProtocol.decoder.decode([IssueMetadata].self, from: response.body)
        #expect(metas.count == 2)
        #expect(metas[0].id == "0001")
        #expect(metas[0].status == "open")
        #expect(metas[0].modules == ["Services", "State"])
        #expect(metas[1].status == "in-progress")
        #expect(metas[1].platform == "All")
    }

    @Test func issuesListUnknownFolderReturns404() throws {
        let store = StubStore()
        let response = try RemoteHandlers.issues(store: store, captures: ["folderId": "missing"])
        #expect(response.status == 404)
    }

    // MARK: - /v1/folders/{folderId}/issues/{id}

    @Test func issueDetailReturnsBodyAndAttachments() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        // Write a real issue file so the handler can read its body.
        let issueURL = folder.appendingPathComponent("0001.md")
        let raw = """
        # 0001 — Sample issue

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | Services |
        | **Platform** | macOS |
        | **First seen** | 2026-05-09 |

        ## Description

        First paragraph.

        ## Notes

        Trailing notes.
        """
        try raw.write(to: issueURL, atomically: true, encoding: .utf8)

        // Also create an attachments folder.
        let attachmentsDir = folder.appendingPathComponent("0001", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        try Data().write(to: attachmentsDir.appendingPathComponent("screenshot.png"))

        let store = StubStore()
        store.folders = [
            Self.makeFolder(
                id: "eeeeeeeeeeeeeeee",
                url: folder,
                issues: [Self.makeIssue(id: "0001", fileURL: issueURL, hasAttachments: true)]
            )
        ]
        let response = try RemoteHandlers.issueDetail(
            store: store,
            captures: ["folderId": "eeeeeeeeeeeeeeee", "id": "0001"]
        )
        #expect(response.status == 200)
        let detail = try RemoteProtocol.decoder.decode(IssueDetail.self, from: response.body)
        #expect(detail.metadata.id == "0001")
        #expect(detail.body.hasPrefix("## Description"))
        #expect(detail.body.contains("First paragraph."))
        #expect(detail.body.contains("## Notes"))
        #expect(detail.attachments == ["screenshot.png"])
    }

    @Test func issueDetailUnknownIssueReturns404() throws {
        let store = StubStore()
        store.folders = [Self.makeFolder(id: "ffffffffffffffff", issues: [])]
        let response = try RemoteHandlers.issueDetail(
            store: store,
            captures: ["folderId": "ffffffffffffffff", "id": "9999"]
        )
        #expect(response.status == 404)
    }

    // MARK: - Body extractor

    @Test func bodyStripsTitleAndMetadataTable() {
        let raw = """
        # 0001 — Sample

        | | |
        |---|---|
        | **Status** | open |

        ## Description

        Hello.
        """
        let body = MarkdownIssueParser.body(from: raw)
        #expect(body.hasPrefix("## Description"))
        #expect(body.contains("Hello."))
    }

    @Test func bodyOmittingTableYieldsRest() {
        let raw = """
        # 0001 — Bare title

        ## Description

        No metadata.
        """
        let body = MarkdownIssueParser.body(from: raw)
        // Should at least retain the Description text — table is optional.
        #expect(body.contains("No metadata."))
    }

    // MARK: - Wire round-trip

    @Test func issueMetadataRoundTripsThroughEncoderDecoder() throws {
        let original = IssueMetadata(
            id: "0042",
            title: "Wire test",
            status: "in-progress",
            modules: ["Services", "State"],
            platform: "macOS",
            firstSeen: Date(timeIntervalSince1970: 1_700_000_123.456),
            closedAt: nil,
            hasAttachments: true,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_999.789)
        )
        let data = try RemoteProtocol.encoder.encode(original)
        let decoded = try RemoteProtocol.decoder.decode(IssueMetadata.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Helpers

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyRepo-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("issues", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

#endif
