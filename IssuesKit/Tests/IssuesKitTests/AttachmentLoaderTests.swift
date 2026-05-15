import Testing
import Foundation
@testable import IssuesCore

#if os(macOS)

/// Tests for `AttachmentLoader` (#0106). Local-source path exercises real
/// disk reads against a temp folder; the remote-source path is covered by
/// `RemoteHostIssueSource`'s stub-client tests once the loader's
/// in-flight dedup is integrated.
@MainActor
struct AttachmentLoaderTests {

    private static func makeTempIssueFolder() throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("issues-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let attachmentDir = folder.appendingPathComponent("0001", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        let payload = Data((0..<2048).map { UInt8($0 & 0xff) })
        let attachmentURL = attachmentDir.appendingPathComponent("screenshot.png")
        try payload.write(to: attachmentURL)
        return (folder, attachmentURL)
    }

    @Test func loadLocalAttachmentReadsBytesFromDisk() async throws {
        let (folder, attachmentURL) = try Self.makeTempIssueFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = LocalFolderIssueSource(folderURL: folder)
        let loader = AttachmentLoader()
        let bytes = try await loader.load(
            folderId: "local",
            issueId: "0001",
            name: "screenshot.png",
            from: source
        )
        let expected = try Data(contentsOf: attachmentURL)
        #expect(bytes == expected)
    }

    @Test func cacheHitDoesntTouchDisk() async throws {
        let (folder, _) = try Self.makeTempIssueFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = LocalFolderIssueSource(folderURL: folder)
        let loader = AttachmentLoader()
        _ = try await loader.load(folderId: "local", issueId: "0001", name: "screenshot.png", from: source)
        // Delete the file on disk; the cache should still serve.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("0001/screenshot.png"))
        let bytes = try await loader.load(folderId: "local", issueId: "0001", name: "screenshot.png", from: source)
        #expect(bytes.count == 2048)
    }

    @Test func loadMissingFileThrows() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loader-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = LocalFolderIssueSource(folderURL: folder)
        let loader = AttachmentLoader()
        do {
            _ = try await loader.load(folderId: "local", issueId: "0001", name: "nope.png", from: source)
            Issue.record("expected load to throw")
        } catch {
            // Any error is fine; we just verify it doesn't crash or
            // silently return empty bytes.
        }
    }

    @Test func invalidateDropsIssueEntries() async throws {
        let (folder, _) = try Self.makeTempIssueFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = LocalFolderIssueSource(folderURL: folder)
        let loader = AttachmentLoader()
        _ = try await loader.load(folderId: "fid", issueId: "0001", name: "screenshot.png", from: source)
        await loader.invalidate(folderId: "fid", issueId: "0001")
        // After invalidate, deleting the on-disk source confirms the
        // cache no longer serves.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("0001/screenshot.png"))
        do {
            _ = try await loader.load(folderId: "fid", issueId: "0001", name: "screenshot.png", from: source)
            Issue.record("expected load to throw after invalidate + on-disk delete")
        } catch {
            // Expected.
        }
    }
}

#endif
