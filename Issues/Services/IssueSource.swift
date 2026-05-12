import Foundation

/// Source of an `IssueStore`'s data. `LocalFolderIssueSource` reads `.md`
/// files off disk and watches the folder via FSEvents; future implementations
/// (e.g. a remote viewer in `RemoteAccess.md` Phase 3) will speak HTTP/WS to a
/// host. The store itself stays platform-neutral and observes whichever
/// source it was given.
///
/// State semantics:
/// - `issues`, `lintFindings`, `loadError`, `folderInvalidated` are produced
///   by the source on each `reload()` and surfaced unchanged to the host store
///   via `onUpdate`. The store mirrors these into its own observable storage.
/// - On a failed reload, the source preserves the previously-parsed `issues`
///   list and sets `loadError`; the host's "snapshot" baseline therefore stays
///   the same value, which is the intended "don't flip the unseen-changes
///   indicator on failure" behavior.
///
/// Isolation note: the protocol is intentionally not `@MainActor`-annotated so
/// implementations can pick their own isolation (the local source is
/// effectively main-only via FolderWatcher's main-actor callbacks; a future
/// remote source may live on a network-IO actor and offer async overloads).
/// Today's call sites are all on the main actor via `TabsModel`.
protocol IssueSource: AnyObject, Sendable {
    /// Stable identity surrogate. Local sources expose the folder URL the user
    /// picked; remote sources will use a synthetic URL or replace this with a
    /// richer identifier when a second source type lands (RemoteAccess.md Q7).
    ///
    /// Marked `nonisolated` so callers running off the MainActor (e.g.
    /// `AttachmentLoader`'s actor) can read it without an actor hop. The
    /// conformer's backing storage must be immutable / Sendable-readable.
    nonisolated var folderURL: URL { get }

    /// Display label for tab title and window header. Defaults to the parent
    /// folder name; replaced by `projectMetadata?.name` when present (#0075).
    var displayName: String { get }

    /// Decoded `project.json`, or nil when the file is missing/empty/malformed.
    /// Wired up in #0075; this issue introduces the field so #0094's
    /// remote source can populate it without another protocol change.
    var projectMetadata: ProjectMetadata? { get }

    /// Persisted security-scoped bookmark bytes for the local case, or nil
    /// when the source has no bookmark (e.g. a remote source, or a unit
    /// test that constructed the source directly from a URL). Used by
    /// `IssueStore.folderId` so the wire identifier is derived from the
    /// same bytes that survive across launches (#0082).
    var bookmarkData: Data? { get }

    /// Short repo-style label for log lines, e.g. `MyRepo` for
    /// `/path/to/MyRepo/issues`.
    var repoName: String { get }

    /// Latest parsed issue list. Updated by `reload()`. Empty before
    /// `start()` runs.
    var issues: [Issue] { get }

    /// Latest lint findings, recomputed on every `reload()`.
    var lintFindings: [LintFinding] { get }

    /// Last error message from a failed reload. Cleared on the next
    /// successful reload.
    var loadError: String? { get }

    /// `true` when the underlying resource has been torn down (folder deleted
    /// or renamed for the local case; host disconnected for the remote case).
    var folderInvalidated: Bool { get }

    /// Fires whenever any of the observable fields above may have changed —
    /// successful reload, failed reload, or folder invalidation. Hosts mirror
    /// the new values into their own state and decide whether to fan the
    /// signal further.
    var onUpdate: ((any IssueSource) -> Void)? { get set }

    /// Begin observing the underlying resource. The local impl performs an
    /// immediate synchronous `reload()` before returning so callers can read
    /// `issues` right after `start()` lands.
    func start()

    /// Stop observing and release any held resources. Idempotent.
    func stop()

    /// Re-read the full state from the source. The local impl does a directory
    /// walk + parser + lint pass; the remote impl will fetch over HTTP.
    func reload()
}

extension IssueSource {
    /// `true` when this source reads directly from disk (LocalFolderIssueSource).
    /// `false` for sources that mirror another host (RemoteAccess.md Phase 3).
    /// Used by `RemoteServer` fanout (#0101) to avoid rebroadcasting a reload
    /// that was itself driven by a remote viewer — that would form a loop in
    /// a host-and-viewer setup.
    var isLocallySourced: Bool { true }
}
