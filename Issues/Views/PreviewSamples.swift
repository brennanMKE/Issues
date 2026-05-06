#if DEBUG
import Foundation

/// Canonical fixtures for SwiftUI `#Preview` blocks throughout the app. Gated
/// on `#if DEBUG` so the file (and any references to it) is excluded from
/// release builds. See issue 0046.
enum PreviewSamples {
    static let issue = Issue(
        id: "0042",
        title: "Reply button not functional on post cells",
        status: .inProgress,
        statusRaw: "in-progress",
        module: "Views",
        platform: "macOS",
        firstSeen: Date(timeIntervalSinceReferenceDate: 800_000_000),
        firstSeenRaw: "2026-05-01",
        closed: nil,
        closedRaw: "",
        description: "Tapping reply does nothing. The button highlights but no action fires.",
        fileURL: URL(fileURLWithPath: "/tmp/preview/0042.md"),
        modifiedAt: Date()
    )

    static let issueOpen = Issue(
        id: "0007",
        title: "Full-text search across issues with Cmd+F",
        status: .open,
        statusRaw: "open",
        module: "Views / State",
        platform: "macOS",
        firstSeen: Date(timeIntervalSinceReferenceDate: 790_000_000),
        firstSeenRaw: "2026-04-25",
        closed: nil,
        closedRaw: "",
        description: "Add a search field that filters by title + description.",
        fileURL: URL(fileURLWithPath: "/tmp/preview/0007.md"),
        modifiedAt: Date(timeIntervalSinceNow: -3600)
    )

    static let issueResolved = Issue(
        id: "0030",
        title: "Move Theme palette into the Asset catalog",
        status: .resolved,
        statusRaw: "resolved",
        module: "Theme",
        platform: "macOS",
        firstSeen: Date(timeIntervalSinceReferenceDate: 770_000_000),
        firstSeenRaw: "2026-04-15",
        closed: Date(timeIntervalSinceReferenceDate: 780_000_000),
        closedRaw: "2026-04-20",
        description: "Promote inline color values to the asset catalog so designers can iterate.",
        fileURL: URL(fileURLWithPath: "/tmp/preview/0030.md"),
        modifiedAt: Date(timeIntervalSinceNow: -86400)
    )

    static let issues: [Issue] = [issue, issueOpen, issueResolved]

    static let lintFinding = LintFinding(
        fileURL: URL(fileURLWithPath: "/tmp/preview/0007.md"),
        kind: .missingAttachment(path: "screenshot.png"),
        summary: "0007.md references missing attachment screenshot.png"
    )

    static let lintFindings: [LintFinding] = [
        lintFinding,
        LintFinding(
            fileURL: URL(fileURLWithPath: "/tmp/preview/0012.md"),
            kind: .unknownStatus(raw: "in_progress"),
            summary: "0012.md has unknown status \"in_progress\""
        )
    ]

    static let rememberedFolder = RememberedFolder(
        displayPath: "/Users/brennan/Developer/Sample/issues",
        bookmarkData: Data(),
        lastUsed: Date()
    )

    @MainActor
    static func makeStore(withIssues populate: Bool = true) -> IssueStore {
        let store = IssueStore(folderURL: URL(fileURLWithPath: "/tmp/preview"))
        if populate {
            store.setIssuesForPreview(issues)
        }
        return store
    }
}
#endif
