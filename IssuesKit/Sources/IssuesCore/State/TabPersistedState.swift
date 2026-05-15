import Foundation

/// Per-tab UI state that survives across launches and across tab close/reopen.
///
/// Keyed by the tab's resolved folder path (see `TabsModel`'s
/// `perTabState` defaults key). Stored as a single JSON-encoded
/// `[String: TabPersistedState]` blob.
///
/// Schema notes:
/// - Enum-valued fields (`viewMode`, `sortColumn`, status filter values) are
///   persisted as raw `String`s rather than the enum types directly. If a
///   future build adds a new case and a user downgrades, decoding falls back
///   to default rather than failing. The status filter set is encoded as
///   `[String]` so `Codable`'s synthesis stays trivial; `IssueStore.apply`
///   converts it back to `Set<IssueStatus>` and silently drops unknown values.
/// - `searchQuery` defaults to the empty string (matching `IssueStore` init)
///   so a missing entry decodes the same as a tab that's never had a search.
/// - `selectedIssueID` is best-effort: `apply` validates it against the
///   parsed issues list and clears it if the issue no longer exists.
/// - Transient state — `issues`, `lintFindings`, `loadError`,
///   `folderInvalidated` — is recomputed on restore by `IssueStore.start()`
///   and intentionally not persisted.
public struct TabPersistedState: Codable, Hashable, Sendable {
    /// Raw `IssueStatus` values that are currently active filters. Empty set
    /// or nil means "no status filter". Stored as `[String]` for Codable
    /// simplicity (and to be tolerant of unknown values added by future
    /// versions).
    public var statusFilters: [String]
    public var moduleFilter: String?
    public var platformFilter: String?
    /// Tri-state attachment filter raw value (#0071). Optional so a
    /// persisted blob from before the filter existed decodes cleanly with
    /// `nil`, which `IssueStore.apply` treats as the default `.all`.
    public var attachmentFilter: String?
    public var searchQuery: String
    public var viewMode: String
    public var sortColumn: String
    public var sortAscending: Bool
    public var selectedIssueID: String?

    public init(
        statusFilters: [String],
        moduleFilter: String?,
        platformFilter: String?,
        attachmentFilter: String?,
        searchQuery: String,
        viewMode: String,
        sortColumn: String,
        sortAscending: Bool,
        selectedIssueID: String?
    ) {
        self.statusFilters = statusFilters
        self.moduleFilter = moduleFilter
        self.platformFilter = platformFilter
        self.attachmentFilter = attachmentFilter
        self.searchQuery = searchQuery
        self.viewMode = viewMode
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
        self.selectedIssueID = selectedIssueID
    }
}
