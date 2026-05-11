import Testing
import Foundation
@testable import Issues

/// Tests for `ReportGenerator` (#0064). Most coverage is on the pure
/// `buildBody` renderer with a fixed clock + a synthetic store; the
/// `generate(for:)` path is exercised once end-to-end against a temp
/// folder to confirm the file lands under `reports/`.
@MainActor
struct ReportGeneratorTests {

    private static let fixedNow = Date(timeIntervalSince1970: 1_715_000_000)

    private static func makeIssue(
        id: String,
        title: String = "Issue",
        status: IssueStatus = .open,
        module: String = "Services",
        platform: String = "macOS",
        modifiedAt: Date = Date(timeIntervalSince1970: 1_714_900_000),
        closedRaw: String = ""
    ) -> Issues.Issue {
        Issues.Issue(
            id: id,
            title: title,
            status: status,
            statusRaw: status.rawValue,
            module: module,
            platform: platform,
            firstSeen: nil,
            firstSeenRaw: "2026-04-15",
            closed: closedRaw.isEmpty ? nil : Date(),
            closedRaw: closedRaw,
            description: "",
            fileURL: URL(fileURLWithPath: "/tmp/\(id).md"),
            modifiedAt: modifiedAt,
            hasAttachments: false
        )
    }

    private static func makeStore(issues: [Issues.Issue]) -> IssueStore {
        let store = IssueStore(folderURL: URL(fileURLWithPath: "/tmp/test-folder"))
        store.setIssuesForPreview(issues)
        return store
    }

    @Test func bodyIncludesTitleAndTimestamp() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001")])
        let body = ReportGenerator.buildBody(store: store, folder: store.folderURL, now: Self.fixedNow)
        #expect(body.contains("Status report"))
        #expect(body.contains("Generated:"))
        #expect(body.contains("Folder: /tmp/test-folder"))
    }

    @Test func summaryReflectsStatusCounts() {
        let issues = [
            Self.makeIssue(id: "0001", status: .open),
            Self.makeIssue(id: "0002", status: .inProgress),
            Self.makeIssue(id: "0003", status: .resolved),
            Self.makeIssue(id: "0004", status: .resolved),
        ]
        let store = Self.makeStore(issues: issues)
        let body = ReportGenerator.buildBody(store: store, folder: store.folderURL, now: Self.fixedNow)
        #expect(body.contains("**Total issues:** 4"))
        #expect(body.contains("**Open:** 1"))
        #expect(body.contains("**In Progress:** 1"))
        #expect(body.contains("**Resolved:** 2"))
    }

    @Test func openIssuesSectionListsOpenAndInProgress() {
        let issues = [
            Self.makeIssue(id: "0001", title: "Alpha", status: .open),
            Self.makeIssue(id: "0002", title: "Beta", status: .inProgress),
            Self.makeIssue(id: "0003", title: "Gamma", status: .resolved),
        ]
        let store = Self.makeStore(issues: issues)
        let body = ReportGenerator.buildBody(store: store, folder: store.folderURL, now: Self.fixedNow)
        #expect(body.contains("| 0001 | Alpha"))
        #expect(body.contains("| 0002 | Beta"))
        #expect(!body.contains("| 0003 | Gamma")) // resolved shouldn't appear
    }

    @Test func emptyStoreRendersNoIssuesYet() {
        let store = Self.makeStore(issues: [])
        let body = ReportGenerator.buildBody(store: store, folder: store.folderURL, now: Self.fixedNow)
        #expect(body.contains("No issues yet."))
    }

    @Test func recentActivityIncludesIssuesWithinFourteenDays() {
        // Just inside the 14-day window.
        let recent = Date(timeIntervalSince1970: Self.fixedNow.timeIntervalSince1970 - 5 * 24 * 3600)
        // Just outside.
        let old = Date(timeIntervalSince1970: Self.fixedNow.timeIntervalSince1970 - 20 * 24 * 3600)
        let issues = [
            Self.makeIssue(id: "0001", title: "Recent", modifiedAt: recent),
            Self.makeIssue(id: "0002", title: "Old", modifiedAt: old)
        ]
        let store = Self.makeStore(issues: issues)
        let body = ReportGenerator.buildBody(store: store, folder: store.folderURL, now: Self.fixedNow)
        #expect(body.contains("#0001"))
        // The "Old" issue's title still appears in the Open issues table,
        // but should not appear in the activity section.
        let activitySection = body.components(separatedBy: "## Recent activity").last ?? ""
        #expect(!activitySection.contains("#0002"))
    }

    @Test func titleWithPipeIsEscaped() {
        let issues = [Self.makeIssue(id: "0001", title: "Has | pipe")]
        let store = Self.makeStore(issues: issues)
        let body = ReportGenerator.buildBody(store: store, folder: store.folderURL, now: Self.fixedNow)
        #expect(body.contains("Has \\| pipe"))
    }

    @Test func generateWritesIntoReportsSubfolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("issues-report-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = IssueStore(folderURL: folder)
        store.setIssuesForPreview([Self.makeIssue(id: "0001")])

        let url = try ReportGenerator.generate(for: store, now: Self.fixedNow)
        #expect(url.path.contains("/reports/"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("Status report"))
    }

    @Test func generateAppendsCounterOnFilenameCollision() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("issues-report-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = IssueStore(folderURL: folder)
        store.setIssuesForPreview([])

        let first = try ReportGenerator.generate(for: store, now: Self.fixedNow)
        let second = try ReportGenerator.generate(for: store, now: Self.fixedNow)
        #expect(first != second)
        #expect(second.lastPathComponent.contains("-2"))
    }
}
