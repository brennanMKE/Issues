import Testing
import Foundation
@testable import IssuesCore

/// Tests for `FolderBookmarkService.pruned(_:)` — the pure cap/sort helper
/// that bounds the remembered-folders list to `maxRemembered` (#0144).
///
/// The cap is tested through this helper rather than `remember(url:)` because
/// recording a folder creates a real security-scoped bookmark, which requires
/// the sandbox entitlement and a live URL. The helper isolates the sort +
/// trim contract so it can be exercised with synthetic entries.
@MainActor
struct FolderBookmarkServiceTests {

    private func folder(_ path: String, daysAgo: Int) -> RememberedFolder {
        RememberedFolder(
            displayPath: path,
            bookmarkData: Data(path.utf8),
            lastUsed: Date(timeIntervalSince1970: 1_000_000 - Double(daysAgo) * 86_400)
        )
    }

    @Test func keepsAllWhenUnderCap() {
        let input = (0..<5).map { folder("/p/\($0)", daysAgo: $0) }
        let result = FolderBookmarkService.pruned(input)
        #expect(result.count == 5)
    }

    @Test func capsAtMaxRemembered() {
        let input = (0..<25).map { folder("/p/\($0)", daysAgo: $0) }
        let result = FolderBookmarkService.pruned(input)
        #expect(result.count == FolderBookmarkService.maxRemembered)
    }

    @Test func keepsMostRecentlyUsedAfterCapping() {
        // daysAgo 0 is the most recent. Feed them out of order to confirm the
        // helper sorts before trimming.
        let input = (0..<25).map { folder("/p/\($0)", daysAgo: $0) }.shuffled()
        let result = FolderBookmarkService.pruned(input)
        // The 10 kept entries should be daysAgo 0..<10, i.e. paths /p/0../p/9.
        let keptPaths = Set(result.map(\.displayPath))
        for i in 0..<FolderBookmarkService.maxRemembered {
            #expect(keptPaths.contains("/p/\(i)"))
        }
        #expect(!keptPaths.contains("/p/10"))
    }

    @Test func resultIsSortedByLastUsedDescending() {
        let input = (0..<25).map { folder("/p/\($0)", daysAgo: $0) }.shuffled()
        let result = FolderBookmarkService.pruned(input)
        let times = result.map(\.lastUsed)
        #expect(times == times.sorted(by: >))
    }
}
