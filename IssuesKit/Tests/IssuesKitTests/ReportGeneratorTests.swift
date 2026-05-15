import Testing
import Foundation
@testable import IssuesCore
@testable import IssuesAppKit

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
    ) -> IssuesCore.Issue {
        IssuesCore.Issue(
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

    private static func makeStore(issues: [IssuesCore.Issue]) -> IssueStore {
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

    @Test func generateWritesStatusDonutPNGAlongsideMarkdown() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("issues-report-png-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = IssueStore(folderURL: folder)
        store.setIssuesForPreview([
            Self.makeIssue(id: "0001", status: .open),
            Self.makeIssue(id: "0002", status: .resolved)
        ])

        let mdURL = try ReportGenerator.generate(for: store, now: Self.fixedNow)
        let pngURL = mdURL.deletingPathExtension().appendingPathExtension("png")
        #expect(FileManager.default.fileExists(atPath: pngURL.path))

        let md = try String(contentsOf: mdURL, encoding: .utf8)
        #expect(md.contains("![Status snapshot](\(pngURL.lastPathComponent))"))

        // Sanity: PNG has the file signature.
        let pngData = try Data(contentsOf: pngURL)
        #expect(pngData.count > 100)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == signature)
    }

    @Test func generateSkipsDonutForEmptyStore() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("issues-report-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = IssueStore(folderURL: folder)
        store.setIssuesForPreview([])

        let mdURL = try ReportGenerator.generate(for: store, now: Self.fixedNow)
        let pngURL = mdURL.deletingPathExtension().appendingPathExtension("png")
        #expect(!FileManager.default.fileExists(atPath: pngURL.path))

        let md = try String(contentsOf: mdURL, encoding: .utf8)
        #expect(!md.contains("![Status snapshot]"))
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
