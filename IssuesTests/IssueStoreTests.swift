import Testing
import Foundation
@testable import Issues

/// Tests for `IssueStore.apply(_:)` (per-tab persisted-state restore, #0009)
/// and the keyboard-nav helpers `selectNext()` / `selectPrevious()` (#0049).
///
/// `IssueStore` isn't `@MainActor`-isolated as a class, but its mutating
/// methods are exercised here on a single test actor. We seed `issues` via
/// the DEBUG-only `setIssuesForPreview(_:)` hook so we never touch disk.
struct IssueStoreTests {

    // MARK: - Fixtures

    private static func makeIssue(
        id: String,
        status: IssueStatus = .open,
        module: String = "State",
        platform: String = "macOS",
        modifiedAt: Date = Date(timeIntervalSince1970: 0),
        hasAttachments: Bool = false
    ) -> Issues.Issue {
        Issues.Issue(
            id: id,
            title: "Issue \(id)",
            status: status,
            statusRaw: status.rawValue,
            module: module,
            platform: platform,
            firstSeen: nil,
            firstSeenRaw: "",
            closed: nil,
            closedRaw: "",
            description: "",
            fileURL: URL(fileURLWithPath: "/tmp/\(id).md"),
            modifiedAt: modifiedAt,
            hasAttachments: hasAttachments
        )
    }

    private static func makeStore(issues: [Issues.Issue]) -> IssueStore {
        let store = IssueStore(folderURL: URL(fileURLWithPath: "/tmp/test-store"))
        store.setIssuesForPreview(issues)
        return store
    }

    // MARK: - apply: round-trip

    @Test func applyRoundTripPreservesEveryField() {
        let issues = [
            Self.makeIssue(id: "0001", status: .open, module: "State", platform: "macOS"),
            Self.makeIssue(id: "0002", status: .inProgress, module: "Services", platform: "macOS"),
        ]
        let source = Self.makeStore(issues: issues)
        source.statusFilters = [.open, .inProgress]
        source.moduleFilter = "State"
        source.platformFilter = "macOS"
        source.searchQuery = "session"
        source.viewMode = .list
        source.sortColumn = .title
        source.sortAscending = false
        source.selectedIssueID = "0002"

        let persisted = source.persistedState()

        let target = Self.makeStore(issues: issues)
        target.apply(persisted)

        #expect(target.statusFilters == [.open, .inProgress])
        #expect(target.moduleFilter == "State")
        #expect(target.platformFilter == "macOS")
        #expect(target.searchQuery == "session")
        #expect(target.viewMode == .list)
        #expect(target.sortColumn == .title)
        #expect(target.sortAscending == false)
        #expect(target.selectedIssueID == "0002")
    }

    // MARK: - apply: filter validation

    @Test func applyDropsUnknownStatusFilterValuesSilently() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001")])
        let state = TabPersistedState(
            statusFilters: ["open", "no-such-status", "inProgress" /* underscore-folded raw */],
            moduleFilter: nil,
            platformFilter: nil,
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "swimlane",
            sortColumn: "id",
            sortAscending: true,
            selectedIssueID: nil
        )
        store.apply(state)
        // Only the canonical "open" rawValue survives.
        #expect(store.statusFilters == [.open])
    }

    @Test func applyClearsStaleModuleFilter() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001", module: "State")])
        let state = TabPersistedState(
            statusFilters: [],
            moduleFilter: "Vanished",
            platformFilter: nil,
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "swimlane",
            sortColumn: "id",
            sortAscending: true,
            selectedIssueID: nil
        )
        store.apply(state)
        #expect(store.moduleFilter == nil)
    }

    @Test func applyKeepsValidModuleFilter() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001", module: "State")])
        let state = TabPersistedState(
            statusFilters: [],
            moduleFilter: "State",
            platformFilter: nil,
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "swimlane",
            sortColumn: "id",
            sortAscending: true,
            selectedIssueID: nil
        )
        store.apply(state)
        #expect(store.moduleFilter == "State")
    }

    @Test func applyClearsStalePlatformFilter() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001", platform: "macOS")])
        let state = TabPersistedState(
            statusFilters: [],
            moduleFilter: nil,
            platformFilter: "tvOS",
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "swimlane",
            sortColumn: "id",
            sortAscending: true,
            selectedIssueID: nil
        )
        store.apply(state)
        #expect(store.platformFilter == nil)
    }

    @Test func applyClearsStaleSelectedIssueID() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001")])
        let state = TabPersistedState(
            statusFilters: [],
            moduleFilter: nil,
            platformFilter: nil,
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "swimlane",
            sortColumn: "id",
            sortAscending: true,
            selectedIssueID: "9999"
        )
        store.apply(state)
        #expect(store.selectedIssueID == nil)
    }

    // MARK: - apply: enum fallback

    @Test func applyFallsBackOnCorruptViewModeRawValue() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001")])
        // Default after init is `.swimlane`; corrupt raw should leave it
        // untouched rather than crash.
        store.viewMode = .swimlane
        let state = TabPersistedState(
            statusFilters: [],
            moduleFilter: nil,
            platformFilter: nil,
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "definitely-not-a-mode",
            sortColumn: "id",
            sortAscending: true,
            selectedIssueID: nil
        )
        store.apply(state)
        #expect(store.viewMode == .swimlane)
    }

    @Test func applyFallsBackOnCorruptSortColumnRawValue() {
        let store = Self.makeStore(issues: [Self.makeIssue(id: "0001")])
        store.sortColumn = .id
        let state = TabPersistedState(
            statusFilters: [],
            moduleFilter: nil,
            platformFilter: nil,
            attachmentFilter: nil,
            searchQuery: "",
            viewMode: "swimlane",
            sortColumn: "definitely-not-a-column",
            sortAscending: true,
            selectedIssueID: nil
        )
        store.apply(state)
        #expect(store.sortColumn == .id)
    }

    // MARK: - selectNext / selectPrevious wrap-around

    @Test func selectNextWrapsAroundAtEnd() {
        let issues = [
            Self.makeIssue(id: "0001"),
            Self.makeIssue(id: "0002"),
            Self.makeIssue(id: "0003"),
        ]
        let store = Self.makeStore(issues: issues)
        store.viewMode = .list
        store.selectedIssueID = "0003"
        store.selectNext()
        #expect(store.selectedIssueID == "0001")
    }

    @Test func selectPreviousWrapsAroundAtStart() {
        let issues = [
            Self.makeIssue(id: "0001"),
            Self.makeIssue(id: "0002"),
            Self.makeIssue(id: "0003"),
        ]
        let store = Self.makeStore(issues: issues)
        store.viewMode = .list
        store.selectedIssueID = "0001"
        store.selectPrevious()
        #expect(store.selectedIssueID == "0003")
    }

    @Test func selectNextWithNoSelectionPicksFirst() {
        let issues = [
            Self.makeIssue(id: "0001"),
            Self.makeIssue(id: "0002"),
        ]
        let store = Self.makeStore(issues: issues)
        store.viewMode = .list
        store.selectedIssueID = nil
        store.selectNext()
        #expect(store.selectedIssueID == "0001")
    }

    @Test func selectPreviousWithNoSelectionPicksLast() {
        let issues = [
            Self.makeIssue(id: "0001"),
            Self.makeIssue(id: "0002"),
        ]
        let store = Self.makeStore(issues: issues)
        store.viewMode = .list
        store.selectedIssueID = nil
        store.selectPrevious()
        #expect(store.selectedIssueID == "0002")
    }

    @Test func selectNextOnEmptyOrderIsNoOp() {
        let store = Self.makeStore(issues: [])
        store.viewMode = .list
        store.selectedIssueID = nil
        store.selectNext()
        #expect(store.selectedIssueID == nil)
    }

    @Test func selectPreviousOnEmptyOrderIsNoOp() {
        let store = Self.makeStore(issues: [])
        store.viewMode = .list
        store.selectedIssueID = nil
        store.selectPrevious()
        #expect(store.selectedIssueID == nil)
    }
}
