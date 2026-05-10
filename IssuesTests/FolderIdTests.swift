import Testing
import Foundation
@testable import Issues

/// Tests for `FolderBookmarkService.folderId(for:)` and the
/// `IssueStore.folderId` passthrough (#0082).
///
/// These tests use synthetic `Data` blobs rather than real security-scoped
/// bookmarks; the function under test is a pure SHA-256 + truncate, so the
/// shape of the input doesn't matter for the contract we're verifying.
struct FolderIdTests {

    // MARK: - Format

    @Test func folderIdIs16LowercaseHexCharacters() {
        let id = FolderBookmarkService.folderId(for: Data("anything".utf8))
        #expect(id.count == 16)
        #expect(id.allSatisfy { $0.isHexDigit })
        #expect(id == id.lowercased())
    }

    @Test func folderIdIsDeterministicForSameBytes() {
        let bytes = Data((0..<128).map { UInt8($0) })
        let a = FolderBookmarkService.folderId(for: bytes)
        let b = FolderBookmarkService.folderId(for: bytes)
        #expect(a == b)
    }

    @Test func folderIdDiffersForDifferentBytes() {
        let a = FolderBookmarkService.folderId(for: Data([0x01]))
        let b = FolderBookmarkService.folderId(for: Data([0x02]))
        #expect(a != b)
    }

    @Test func folderIdMatchesKnownVector() {
        // SHA-256("") starts with e3b0c44298fc1c14... — first 16 hex chars
        // are the first 8 bytes of the digest as lowercase hex.
        let id = FolderBookmarkService.folderId(for: Data())
        #expect(id == "e3b0c44298fc1c14")
    }

    // MARK: - IssueStore passthrough

    @Test func issueStoreFolderIdIsNilWithoutBookmark() {
        let store = IssueStore(folderURL: URL(fileURLWithPath: "/tmp/no-bookmark"))
        #expect(store.folderId == nil)
        #expect(store.bookmarkData == nil)
    }

    @Test func issueStoreFolderIdMatchesServiceForSameBytes() {
        let bytes = Data("synthetic-bookmark".utf8)
        let store = IssueStore(
            folderURL: URL(fileURLWithPath: "/tmp/with-bookmark"),
            bookmarkData: bytes
        )
        let expected = FolderBookmarkService.folderId(for: bytes)
        #expect(store.folderId == expected)
        #expect(store.bookmarkData == bytes)
    }
}
