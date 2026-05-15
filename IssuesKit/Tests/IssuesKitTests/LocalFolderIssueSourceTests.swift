import Testing
import Foundation
@testable import IssuesCore

/// Tests for `LocalFolderIssueSource.projectMetadata` / `displayName`
/// (#0075 — read `project.json`).
///
/// Each test writes into a fresh temp folder, calls `reload()` directly
/// (skipping `start()` so the FolderWatcher / security-scoped paths stay out
/// of the picture), and asserts on `projectMetadata` and `displayName`.
@MainActor
struct LocalFolderIssueSourceTests {

    // MARK: - Fixture

    private static func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyRepo-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("issues", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeProjectJSON(_ contents: String, in folder: URL) throws {
        try contents.write(
            to: folder.appendingPathComponent("project.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Cases

    @Test func projectJSONPresent_validName_drivesDisplayName() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try Self.writeProjectJSON(#"""
        {
          "name": "Issues.app",
          "url": "https://github.com/brennanMKE/Issues"
        }
        """#, in: folder)

        let source = LocalFolderIssueSource(folderURL: folder)
        source.reload()

        #expect(source.projectMetadata?.name == "Issues.app")
        #expect(source.projectMetadata?.url == URL(string: "https://github.com/brennanMKE/Issues"))
        #expect(source.displayName == "Issues.app")
    }

    @Test func projectJSONPresent_missingName_fallsBackToRepoName() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try Self.writeProjectJSON(#"""
        { "url": "https://github.com/brennanMKE/Issues" }
        """#, in: folder)

        let source = LocalFolderIssueSource(folderURL: folder)
        source.reload()

        #expect(source.projectMetadata != nil)
        #expect(source.projectMetadata?.name == nil)
        // The temp folder's parent is `MyRepo-<uuid>`; `repoName` is that name.
        #expect(source.displayName == source.repoName)
        #expect(source.repoName.hasPrefix("MyRepo-"))
    }

    @Test func projectJSONPresent_emptyName_fallsBackToRepoName() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try Self.writeProjectJSON(#"""
        { "name": "", "url": "https://example.com" }
        """#, in: folder)

        let source = LocalFolderIssueSource(folderURL: folder)
        source.reload()

        #expect(source.projectMetadata?.name == "")
        #expect(source.displayName == source.repoName)
    }

    @Test func projectJSONMalformed_metadataNil_displayNameFallsBack() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try Self.writeProjectJSON("{ this is not json", in: folder)

        let source = LocalFolderIssueSource(folderURL: folder)
        source.reload()

        #expect(source.projectMetadata == nil)
        #expect(source.displayName == source.repoName)
    }

    @Test func projectJSONAbsent_metadataNil_displayNameIsRepoName() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        let source = LocalFolderIssueSource(folderURL: folder)
        source.reload()

        #expect(source.projectMetadata == nil)
        #expect(source.displayName == source.repoName)
    }

    @Test func projectJSONReReadOnReload() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        let source = LocalFolderIssueSource(folderURL: folder)
        source.reload()
        #expect(source.displayName == source.repoName)

        // Add a project.json — next reload picks it up.
        try Self.writeProjectJSON(#"{ "name": "Bluesky" }"#, in: folder)
        source.reload()
        #expect(source.displayName == "Bluesky")

        // Edit the name — next reload reflects it.
        try Self.writeProjectJSON(#"{ "name": "Bluesky for SwiftUI" }"#, in: folder)
        source.reload()
        #expect(source.displayName == "Bluesky for SwiftUI")

        // Delete the file — fall back to repo name.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("project.json"))
        source.reload()
        #expect(source.projectMetadata == nil)
        #expect(source.displayName == source.repoName)
    }
}
