import Testing
import IssuesCore
import Foundation
@testable import Issues

/// Tests for `TabsModel.diff(baseline:new:issues:)` — the pure value-typed
/// computation that drives notification firing (#0013) and underpins the
/// per-tab "unseen changes" indicator.
///
/// Body-only edits (same id, same status, different `modifiedAt`) intentionally
/// don't surface in `diff`: the dot indicator already tracks them and we don't
/// want banner spam on every keystroke. This contract is pinned down below.
///
/// `TabsModel` is `@MainActor`-isolated, so `static` methods on it are too;
/// the suite is therefore `@MainActor` to call `diff` directly.
@MainActor
struct TabsModelTests {

    // MARK: - Fixtures

    private static func makeIssue(
        id: String,
        status: IssueStatus = .open,
        modifiedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> IssuesCore.Issue {
        IssuesCore.Issue(
            id: id,
            title: "Issue \(id)",
            status: status,
            statusRaw: status.rawValue,
            module: "State",
            platform: "macOS",
            firstSeen: nil,
            firstSeenRaw: "",
            closed: nil,
            closedRaw: "",
            description: "",
            fileURL: URL(fileURLWithPath: "/tmp/\(id).md"),
            modifiedAt: modifiedAt,
            hasAttachments: false
        )
    }

    private static func snapshot(_ issue: IssuesCore.Issue) -> IssueSnapshot {
        IssueSnapshot(id: issue.id, status: issue.status, modifiedAt: issue.modifiedAt)
    }

    // MARK: - diff

    @Test func diffReturnsEmptyWhenIdentical() {
        let issues = [
            Self.makeIssue(id: "0001"),
            Self.makeIssue(id: "0002", status: .inProgress),
        ]
        let snap = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, Self.snapshot($0)) })

        let result = TabsModel.diff(baseline: snap, new: snap, issues: issues)
        #expect(result.additions.isEmpty)
        #expect(result.removals.isEmpty)
        #expect(result.statusChanges.isEmpty)
    }

    @Test func diffNewIDProducesAddition() {
        let existing = Self.makeIssue(id: "0001")
        let added = Self.makeIssue(id: "0002")
        let baseline = [existing.id: Self.snapshot(existing)]
        let new = Dictionary(uniqueKeysWithValues: [existing, added].map { ($0.id, Self.snapshot($0)) })

        let result = TabsModel.diff(
            baseline: baseline,
            new: new,
            issues: [existing, added]
        )
        #expect(result.additions.map { $0.id } == ["0002"])
        #expect(result.removals.isEmpty)
        #expect(result.statusChanges.isEmpty)
    }

    @Test func diffMissingIDProducesPlaceholderRemoval() {
        let kept = Self.makeIssue(id: "0001")
        let removed = Self.makeIssue(id: "0002", status: .inProgress)
        let baseline = Dictionary(uniqueKeysWithValues: [kept, removed].map { ($0.id, Self.snapshot($0)) })
        let new = [kept.id: Self.snapshot(kept)]

        let result = TabsModel.diff(
            baseline: baseline,
            new: new,
            issues: [kept] // `removed` is no longer present
        )
        #expect(result.additions.isEmpty)
        #expect(result.statusChanges.isEmpty)
        #expect(result.removals.count == 1)
        let placeholder = try? #require(result.removals.first)
        #expect(placeholder?.id == "0002")
        // Last-known status survives via the synthesized placeholder.
        #expect(placeholder?.status == .inProgress)
        #expect(placeholder?.statusRaw == IssueStatus.inProgress.rawValue)
        // Title is intentionally blank — runner can't reconstruct it.
        #expect(placeholder?.title == "")
    }

    @Test func diffStatusChangeIsClassifiedAsChangeNotAddOrRemove() {
        let before = Self.makeIssue(id: "0001", status: .open)
        let after = Self.makeIssue(id: "0001", status: .resolved)
        let baseline = [before.id: Self.snapshot(before)]
        let new = [after.id: Self.snapshot(after)]

        let result = TabsModel.diff(
            baseline: baseline,
            new: new,
            issues: [after]
        )
        #expect(result.additions.isEmpty)
        #expect(result.removals.isEmpty)
        #expect(result.statusChanges.count == 1)
        let change = try? #require(result.statusChanges.first)
        #expect(change?.issue.id == "0001")
        #expect(change?.oldStatus == .open)
        #expect(change?.newStatus == .resolved)
    }

    @Test func diffBodyOnlyEditDoesNotSurface() {
        // Same id, same status, different modifiedAt → no entries.
        let early = Self.makeIssue(
            id: "0001",
            status: .open,
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
        let later = Self.makeIssue(
            id: "0001",
            status: .open,
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let baseline = [early.id: Self.snapshot(early)]
        let new = [later.id: Self.snapshot(later)]

        let result = TabsModel.diff(
            baseline: baseline,
            new: new,
            issues: [later]
        )
        #expect(result.additions.isEmpty)
        #expect(result.removals.isEmpty)
        #expect(result.statusChanges.isEmpty)
    }

    @Test func diffMixedChangesAreAllClassifiedCorrectly() {
        // Baseline: 0001 (open), 0002 (open), 0003 (open)
        // New:      0002 (resolved), 0003 (open), 0004 (open)
        //   → 0001 removed, 0004 added, 0002 status change.
        let b1 = Self.makeIssue(id: "0001", status: .open)
        let b2 = Self.makeIssue(id: "0002", status: .open)
        let b3 = Self.makeIssue(id: "0003", status: .open)

        let n2 = Self.makeIssue(id: "0002", status: .resolved)
        let n3 = b3
        let n4 = Self.makeIssue(id: "0004", status: .open)

        let baseline = Dictionary(uniqueKeysWithValues: [b1, b2, b3].map { ($0.id, Self.snapshot($0)) })
        let new = Dictionary(uniqueKeysWithValues: [n2, n3, n4].map { ($0.id, Self.snapshot($0)) })

        let result = TabsModel.diff(
            baseline: baseline,
            new: new,
            issues: [n2, n3, n4]
        )
        #expect(result.additions.map { $0.id } == ["0004"])
        #expect(result.removals.map { $0.id } == ["0001"])
        #expect(result.statusChanges.count == 1)
        let change = try? #require(result.statusChanges.first)
        #expect(change?.issue.id == "0002")
        #expect(change?.oldStatus == .open)
        #expect(change?.newStatus == .resolved)
    }
}
