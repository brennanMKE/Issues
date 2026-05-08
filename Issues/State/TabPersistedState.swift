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
struct TabPersistedState: Codable, Hashable {
    /// Raw `IssueStatus` values that are currently active filters. Empty set
    /// or nil means "no status filter". Stored as `[String]` for Codable
    /// simplicity (and to be tolerant of unknown values added by future
    /// versions).
    var statusFilters: [String]
    var moduleFilter: String?
    var platformFilter: String?
    /// Tri-state attachment filter raw value (#0071). Optional so a
    /// persisted blob from before the filter existed decodes cleanly with
    /// `nil`, which `IssueStore.apply` treats as the default `.all`.
    var attachmentFilter: String?
    var searchQuery: String
    var viewMode: String
    var sortColumn: String
    var sortAscending: Bool
    var selectedIssueID: String?
}
