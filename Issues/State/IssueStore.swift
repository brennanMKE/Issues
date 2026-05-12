import Foundation
import Observation

@Observable
final class IssueStore: Identifiable {

    enum ViewMode: String, CaseIterable, Hashable {
        case swimlane, timeline, list, recent

        var displayName: String {
            switch self {
            case .swimlane: return "Swimlanes"
            case .timeline: return "Timeline"
            case .list: return "List"
            case .recent: return "Recent"
            }
        }
    }

    enum SortColumn: String, Hashable {
        case id, status, title, module, platform, firstSeen
    }

    /// Tri-state filter on attachment presence (#0071). The signal is
    /// "sibling `<id>/` folder exists and contains at least one regular
    /// file" — captured per-issue in `Issue.hasAttachments` during the
    /// source's reload pass. Composed AND-style with the status / module /
    /// platform / search filters in `filteredIssues`.
    enum AttachmentFilter: String, CaseIterable, Hashable {
        case all, withAttachments, withoutAttachments

        var displayName: String {
            switch self {
            case .all: return "All Attachments"
            case .withAttachments: return "With attachments"
            case .withoutAttachments: return "Without attachments"
            }
        }
    }

    /// Stable per-store identity used as the tab id by `TabsModel`. Survives
    /// across reloads; not persisted (tabs are persisted by bookmark, ids are
    /// regenerated on launch).
    let id: UUID = UUID()

    /// File-IO and watcher concerns live here. The store holds the source as
    /// an existential so a remote source (RemoteAccess.md Phase 3, #0094) can
    /// drop in without touching this layer.
    private let source: any IssueSource

    private(set) var issues: [Issue] = []
    /// Read-only lint findings produced by `LintRunner` after each successful
    /// reload. Surfaced via the lint banner in `StatsBarView` (#0019); empty
    /// list means a clean folder. Mirrored from the source on every update so
    /// it stays in sync with `issues`.
    private(set) var lintFindings: [LintFinding] = []
    private(set) var loadError: String?
    private(set) var folderInvalidated: Bool = false

    var statusFilters: Set<IssueStatus> = []
    var moduleFilter: String?
    var platformFilter: String?
    var attachmentFilter: AttachmentFilter = .all
    var searchQuery: String = ""
    var viewMode: ViewMode = .swimlane
    var selectedIssueID: String?
    var sortColumn: SortColumn = .id
    var sortAscending: Bool = true

    /// Issue queued for a confirmed reveal (#0070). Set by `requestReveal`
    /// when the target row would otherwise be hidden by the current
    /// filters / search / view mode; `MainView` surfaces a confirmation
    /// dialog and calls `revealIssue` on confirm or clears on cancel.
    var pendingReveal: Issue?

    /// Fires after every successful reload (issues populated, no error). Used
    /// by `TabsModel` to drive the per-tab "unseen changes" indicator. Not
    /// fired on read failures or folder-invalidation ticks — those leave
    /// `issues` untouched and shouldn't flip the indicator.
    var onReload: ((IssueStore) -> Void)?

    /// Fires alongside `onReload` for successful, locally-sourced reloads
    /// only. Used by `RemoteHostController` to push reload events down the
    /// WebSocket fanout (#0101). Kept separate from `onReload` so the
    /// TabsModel hook (which already owns `onReload`) doesn't have to
    /// multi-cast, and so a remote-sourced reload (#0094) can't loop back
    /// through the broadcast bus.
    var onReloadBroadcast: ((IssueStore) -> Void)?

    /// The folder URL the source reads from. Local-source surrogate for tab
    /// identity in `TabsModel`'s persistence keys and security-scoped bookmark
    /// path. Future remote sources will replace this with a richer identifier.
    var folderURL: URL { source.folderURL }

    /// Repo-style label for the watched folder, e.g. for a folder
    /// `/path/to/MyRepo/issues` this is `MyRepo`. Used for log labels so
    /// multi-folder log streams stay readable. User-facing labels should use
    /// `displayName` instead so a folder's `project.json` `name` wins.
    var repoName: String { source.repoName }

    /// User-facing label: `projectMetadata?.name` when present, else
    /// `repoName`. Tabs, window title, and notifications use this so a
    /// folder's `project.json` "name" surfaces wherever the parent folder
    /// name used to (#0075).
    var displayName: String { source.displayName }

    /// Decoded `project.json` for the watched folder. Refreshed on every
    /// reload. Currently the `name` field drives `displayName`; `url` is
    /// decoded but not yet surfaced in the UI (tracked in the RemoteAccess
    /// "Open repository" follow-up).
    var projectMetadata: ProjectMetadata? { source.projectMetadata }

    /// Persisted security-scoped bookmark bytes captured when this store
    /// was opened or restored. Exposed so `TabsModel.persist()` can write
    /// the same bytes that were used to derive `folderId` rather than
    /// regenerating a fresh blob from the URL on every save (#0082).
    var bookmarkData: Data? { source.bookmarkData }

    /// Wire-stable identifier for the watched folder, derived from the
    /// security-scoped bookmark bytes via `FolderBookmarkService.folderId`
    /// (#0082). Nil when the source has no bookmark (preview / tests).
    /// Remote sources (#0094) publish their own folder id directly — we
    /// pull it out via `remoteFolderId` so it matches what the host
    /// announced over the wire.
    var folderId: String? {
        if let data = source.bookmarkData {
            return FolderBookmarkService.folderId(for: data)
        }
        if let remote = source as? RemoteHostIssueSource {
            return remote.folderId
        }
        return nil
    }

    /// `true` when this store is backed by a remote host (#0099). Used by
    /// the tab chip to draw a small remote indicator next to the title.
    var isRemote: Bool {
        source is RemoteHostIssueSource
    }

    /// `(host, port)` if this store is backed by a remote source — for
    /// `TabsModel`'s persistence path and the tab tooltip in #0099.
    var remoteEndpoint: (host: String, port: UInt16)? {
        guard let remote = source as? RemoteHostIssueSource else { return nil }
        return (remote.host, remote.port)
    }

    /// Current remote connection state (#0104). Nil for local sources;
    /// the disconnect/expired banner only renders for remote tabs.
    var remoteConnectionState: RemoteConnectionState? {
        (source as? RemoteHostIssueSource)?.connectionState
    }

    /// Convenience init: wraps the URL in a `LocalFolderIssueSource`. Existing
    /// call sites (`TabsModel.openTab(url:)`, restore) keep using this form.
    convenience init(folderURL: URL, bookmarkData: Data? = nil) {
        self.init(source: LocalFolderIssueSource(folderURL: folderURL, bookmarkData: bookmarkData))
    }

    init(source: any IssueSource) {
        self.source = source
        self.source.onUpdate = { [weak self] src in
            self?.handleSourceUpdate(src)
        }
    }

    // MARK: - Lifecycle

    func start() {
        source.start()
    }

    func stop() {
        source.stop()
    }

    /// Force a re-read from the source. Used by the Reload menu command
    /// (`AppCommandsController.reloadActive`).
    func reload() {
        source.reload()
    }

    // MARK: - Loading

    /// Mirror the source's latest state and decide whether to fan the signal
    /// upstream. Called from `IssueSource.onUpdate` after each reload attempt
    /// or watcher invalidation.
    private func handleSourceUpdate(_ src: any IssueSource) {
        self.issues = src.issues
        self.lintFindings = src.lintFindings
        self.loadError = src.loadError
        self.folderInvalidated = src.folderInvalidated
        // Selection cleanup: clear the highlight if the previously-selected
        // issue is no longer present in the parsed list.
        if let id = selectedIssueID, !src.issues.contains(where: { $0.id == id }) {
            selectedIssueID = nil
        }
        // Match today's `onReload` contract: success-only. Failed reloads and
        // folder-invalidation ticks update observable state silently; views
        // re-render via @Observable diffs without the unseen-changes path
        // running.
        if src.loadError == nil && !src.folderInvalidated {
            onReload?(self)
            // Only broadcast for local sources — a remote-sourced reload
            // (#0094) is itself driven by a host broadcast, and rebroadcasting
            // would form a viewer ↔ host loop in host-and-viewer instances.
            if src.isLocallySourced {
                onReloadBroadcast?(self)
            }
        }
    }

    // MARK: - Derived state

    var filteredIssues: [Issue] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedQuery = trimmedQuery.isEmpty ? nil : trimmedQuery.lowercased()
        // Pure-numeric queries also match against the issue id (#0067).
        // "31" matches "0031" via the zero-padded form; "003" matches all
        // "*003*" ids via the substring form. Non-numeric queries continue
        // to use the existing title/description match.
        let numericPaddedID: String? = {
            guard let q = lowercasedQuery,
                  !q.isEmpty,
                  q.allSatisfy(\.isNumber),
                  let value = Int(q) else { return nil }
            return String(format: "%04d", value)
        }()
        return issues.filter { issue in
            if !statusFilters.isEmpty && !statusFilters.contains(issue.status) { return false }
            if let m = moduleFilter, !issue.modules.contains(m) { return false }
            if let p = platformFilter, issue.platform != p, issue.platform != "All" { return false }
            switch attachmentFilter {
            case .all: break
            case .withAttachments where !issue.hasAttachments: return false
            case .withoutAttachments where issue.hasAttachments: return false
            default: break
            }
            if let q = lowercasedQuery {
                let idMatch: Bool = {
                    guard let padded = numericPaddedID else { return false }
                    return issue.id.contains(q) || issue.id.contains(padded)
                }()
                guard idMatch ||
                      issue.title.lowercased().contains(q) ||
                      issue.description.lowercased().contains(q) else { return false }
            }
            return true
        }
    }

    var selectedIssue: Issue? {
        guard let id = selectedIssueID else { return nil }
        return issues.first { $0.id == id }
    }

    func groupedByPrimaryModule(_ list: [Issue]) -> [(module: String, issues: [Issue])] {
        var order: [String] = []
        var buckets: [String: [Issue]] = [:]
        for issue in list {
            let key = issue.primaryModule
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(issue)
        }
        return order.map { (module: $0, issues: buckets[$0] ?? []) }
    }

    var uniqueModules: [String] {
        var set = Set<String>()
        for issue in issues {
            for module in issue.modules where !module.isEmpty {
                set.insert(module)
            }
        }
        return set.sorted()
    }

    var uniquePlatforms: [String] {
        var set = Set<String>()
        for issue in issues where !issue.platform.isEmpty {
            set.insert(issue.platform)
        }
        return set.sorted()
    }

    /// A change-detection view of the current issue list keyed by id. Used by
    /// `TabsModel` to compare the post-reload state against what the user last
    /// saw on this tab.
    var snapshot: [String: IssueSnapshot] {
        var result: [String: IssueSnapshot] = [:]
        result.reserveCapacity(issues.count)
        for issue in issues {
            result[issue.id] = IssueSnapshot(
                id: issue.id,
                status: issue.status,
                modifiedAt: issue.modifiedAt
            )
        }
        return result
    }

    var statusCounts: [IssueStatus: Int] {
        var counts: [IssueStatus: Int] = [:]
        for issue in issues {
            counts[issue.status, default: 0] += 1
        }
        return counts
    }

    // MARK: - Notification-driven reveal (#0070)

    /// Returns true when the issue with `id` would appear in the active
    /// view given the current filters / search / view-mode. Used by the
    /// notification-tap path to decide between a silent selection and the
    /// "Reveal Issue?" confirmation dialog.
    ///
    /// Visibility = the issue is in `filteredIssues` AND the active view
    /// mode would render it. All four view modes today (swimlane,
    /// timeline, list, recent) draw from the same `filteredIssues` set —
    /// the test simplifies to "is the issue in `filteredIssues`?".
    func issueIsCurrentlyVisible(id: String) -> Bool {
        filteredIssues.contains(where: { $0.id == id })
    }

    /// Notification-tap entry point. If the target row is currently
    /// visible, select it immediately (today's behavior). Otherwise
    /// queue it for a user-confirmed reveal — `MainView` shows the
    /// confirmation dialog.
    func requestReveal(id: String) {
        guard let target = issues.first(where: { $0.id == id }) else { return }
        if issueIsCurrentlyVisible(id: id) {
            selectedIssueID = id
        } else {
            pendingReveal = target
        }
    }

    /// User-confirmed reveal: flip to `.list`, clear only the filters and
    /// search query that would hide the target, and select it. Doesn't
    /// touch filters that aren't blocking the row so the user's prior
    /// selections survive as much as possible (#0070's
    /// minimum-clearing principle).
    func revealIssue(_ issue: Issue) {
        viewMode = .list
        if let s = moduleFilter, !issue.modules.contains(s) {
            moduleFilter = nil
        }
        if let p = platformFilter, issue.platform != p && issue.platform != "All" {
            platformFilter = nil
        }
        if !statusFilters.isEmpty && !statusFilters.contains(issue.status) {
            statusFilters = []
        }
        switch attachmentFilter {
        case .all: break
        case .withAttachments where !issue.hasAttachments:
            attachmentFilter = .all
        case .withoutAttachments where issue.hasAttachments:
            attachmentFilter = .all
        default: break
        }
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let q = trimmed.lowercased()
            let matches = issue.id.lowercased().contains(q)
                || issue.title.lowercased().contains(q)
                || issue.description.lowercased().contains(q)
            if !matches { searchQuery = "" }
        }
        selectedIssueID = issue.id
        pendingReveal = nil
    }

    /// Cancels a queued reveal without changing any filters or selection.
    func cancelReveal() {
        pendingReveal = nil
    }

    func toggleSelection(_ id: String) {
        if selectedIssueID == id {
            selectedIssueID = nil
        } else {
            selectedIssueID = id
        }
    }

    func deselect() {
        selectedIssueID = nil
    }

    // MARK: - Keyboard navigation

    /// Issues in the order the active view displays them. The flat order across
    /// view modes:
    /// - List: filtered set sorted by `id` ascending. The view itself can
    ///   override sort via column headers, but for ↑/↓ navigation we use the
    ///   stable id order so the keyboard walk is deterministic regardless of
    ///   column sort. (`Table` already handles its own focused navigation; this
    ///   helper is the fallback.)
    /// - Recent: filtered set by `modifiedAt` descending.
    /// - Swimlanes: grouped by primary module, flattened.
    /// - Timeline: same grouping as Swimlanes (display order matches).
    var visibleIssueOrder: [Issue] {
        let filtered = filteredIssues
        switch viewMode {
        case .list:
            return filtered.sorted { $0.id < $1.id }
        case .recent:
            return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
        case .swimlane, .timeline:
            return groupedByPrimaryModule(filtered).flatMap { $0.issues }
        }
    }

    /// Moves selection to the next issue in `visibleIssueOrder`. Wraps around
    /// at the end. If nothing is selected, picks the first.
    func selectNext() {
        let order = visibleIssueOrder
        guard !order.isEmpty else { return }
        if let id = selectedIssueID, let idx = order.firstIndex(where: { $0.id == id }) {
            selectedIssueID = order[(idx + 1) % order.count].id
        } else {
            selectedIssueID = order.first?.id
        }
    }

    /// Moves selection to the previous issue in `visibleIssueOrder`. Wraps
    /// around at the start. If nothing is selected, picks the last.
    func selectPrevious() {
        let order = visibleIssueOrder
        guard !order.isEmpty else { return }
        if let id = selectedIssueID, let idx = order.firstIndex(where: { $0.id == id }) {
            selectedIssueID = order[(idx - 1 + order.count) % order.count].id
        } else {
            selectedIssueID = order.last?.id
        }
    }

    // MARK: - Persisted-state round-trip (#0009)

    /// Captures the user-visible UI state into a value type suitable for
    /// `UserDefaults`. Transient state (`issues`, `lintFindings`, etc.) is
    /// not included — it's recomputed by `start()` on restore.
    ///
    /// Named `persistedState` to avoid collision with the `snapshot`
    /// property used by `TabsModel` for unseen-change tracking.
    func persistedState() -> TabPersistedState {
        TabPersistedState(
            statusFilters: statusFilters.map { $0.rawValue }.sorted(),
            moduleFilter: moduleFilter,
            platformFilter: platformFilter,
            attachmentFilter: attachmentFilter.rawValue,
            searchQuery: searchQuery,
            viewMode: viewMode.rawValue,
            sortColumn: sortColumn.rawValue,
            sortAscending: sortAscending,
            selectedIssueID: selectedIssueID
        )
    }

    /// Applies a previously-persisted state. Each field is validated against
    /// the current `issues` list so stale module names, platforms, or issue
    /// ids don't leave the UI in an empty / broken state. Unknown enum raw
    /// values fall back to current defaults rather than crashing.
    ///
    /// Must be called *after* `start()` has populated `issues` (via the
    /// source's first reload) so the validity checks have data to compare
    /// against.
    func apply(_ state: TabPersistedState) {
        // Status filters: drop unknown raw values silently.
        var resolvedStatuses: Set<IssueStatus> = []
        for raw in state.statusFilters {
            if let status = IssueStatus(rawValue: raw) {
                resolvedStatuses.insert(status)
            }
        }
        statusFilters = resolvedStatuses

        // Module filter: drop if the module no longer appears in any issue.
        if let saved = state.moduleFilter, uniqueModules.contains(saved) {
            moduleFilter = saved
        } else {
            moduleFilter = nil
        }

        // Platform filter: drop if no current issue uses this platform.
        if let saved = state.platformFilter, uniquePlatforms.contains(saved) {
            platformFilter = saved
        } else {
            platformFilter = nil
        }

        // Attachment filter: fall back to `.all` for missing or unknown raw
        // values so old persisted blobs (pre-#0071) decode cleanly.
        if let raw = state.attachmentFilter, let parsed = AttachmentFilter(rawValue: raw) {
            attachmentFilter = parsed
        } else {
            attachmentFilter = .all
        }

        searchQuery = state.searchQuery

        if let mode = ViewMode(rawValue: state.viewMode) {
            viewMode = mode
        }

        if let column = SortColumn(rawValue: state.sortColumn) {
            sortColumn = column
        }
        sortAscending = state.sortAscending

        // Selection: only restore if the issue is still present. Otherwise
        // leave selection nil — the user will just see no detail panel,
        // which is a fine fallback.
        if let savedID = state.selectedIssueID,
           issues.contains(where: { $0.id == savedID }) {
            selectedIssueID = savedID
        } else {
            selectedIssueID = nil
        }
    }
}

#if DEBUG
extension IssueStore {
    /// Preview-only seam: bypass the source and directly set the in-memory
    /// list. Used by `PreviewSamples.makeStore` and the tests in
    /// `IssueStoreTests`. Lives in the same file as the class so it can write
    /// to `private(set) var issues`.
    func setIssuesForPreview(_ issues: [Issue]) {
        self.issues = issues
    }
}
#endif
