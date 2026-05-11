import Foundation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "RemoteHostIssueSource")

/// `IssueSource` backed by a remote host (#0094). Today this is a stub
/// scaffolding so the picker (#0097) can construct one per chosen folder
/// and `IssueStore` / `TabsModel` can carry it around. Fetching, parsing,
/// and websocket subscription land in #0094 / #0102; this iteration only
/// wires the construction path.
///
/// `folderURL` uses a synthetic `issues-remote://<host>:<port>/<folderId>`
/// scheme so anything that pivots on the URL scheme (e.g. the tab chip's
/// remote indicator, #0099) can identify it without owning a separate
/// "kind" enum.
final class RemoteHostIssueSource: IssueSource {

    /// Synthetic scheme used by the source's `folderURL`. Code that needs to
    /// distinguish local vs. remote tabs without taking a dependency on this
    /// type can check `folderURL.scheme == RemoteHostIssueSource.urlScheme`.
    static let urlScheme = "issues-remote"

    let folderURL: URL
    let host: String
    let port: UInt16
    /// Bearer token used for HTTP/WS authentication. Stored in-memory only;
    /// persistence is in the Keychain via `ViewerTokenStore`.
    let token: String
    let folderId: String

    /// Remote sources don't carry a bookmark — their stable identity is
    /// the `(host, folderId)` tuple, not a filesystem reference.
    var bookmarkData: Data? { nil }

    /// User-visible label. Populated by the first successful `fetchHost` /
    /// folder list response; falls back to the folder id until then.
    var displayName: String {
        if let cached = cachedDisplayName, !cached.isEmpty { return cached }
        return folderId
    }

    var repoName: String { folderId }

    /// `project.json`-equivalent metadata returned by the host (#0075). The
    /// scaffolding source leaves it nil; #0094 will populate from the
    /// `FolderInfo` payload.
    var projectMetadata: ProjectMetadata? { nil }

    private(set) var issues: [Issue] = []
    private(set) var lintFindings: [LintFinding] = []
    private(set) var loadError: String?
    private(set) var folderInvalidated: Bool = false

    var onUpdate: ((any IssueSource) -> Void)?

    /// Optional viewer-facing display name learned from the host (e.g. the
    /// `name` from `FolderInfo`). Set by future fetching code; for now it
    /// can be seeded from the picker so the tab chip has a label.
    var cachedDisplayName: String?

    init(host: String, port: UInt16, token: String, folderId: String, displayName: String? = nil) {
        self.host = host
        self.port = port
        self.token = token
        self.folderId = folderId
        self.cachedDisplayName = displayName
        // `URL(string:)` requires the host segment to be a valid URI host;
        // IPv6 literals get bracketed the same way the HTTP client does.
        let bracketed: String
        if host.contains(":") && !host.hasPrefix("[") {
            bracketed = "[\(host)]"
        } else {
            bracketed = host
        }
        if let url = URL(string: "\(Self.urlScheme)://\(bracketed):\(port)/\(folderId)") {
            self.folderURL = url
        } else {
            // Fallback should never fire (the inputs are validated upstream),
            // but a guaranteed URL keeps `IssueStore` happy.
            self.folderURL = URL(string: "\(Self.urlScheme)://invalid/\(folderId)")!
        }
    }

    // MARK: - Lifecycle

    func start() {
        logger.notice("remote source start host=\(self.host, privacy: .public):\(self.port, privacy: .public) folder=\(self.folderId, privacy: .public)")
        // #0094 will perform the initial fetch + websocket subscribe here.
        // For this iteration we just publish the (empty) initial state so
        // the store's @Observable wiring fires.
        onUpdate?(self)
    }

    func stop() {
        logger.notice("remote source stop host=\(self.host, privacy: .public):\(self.port, privacy: .public) folder=\(self.folderId, privacy: .public)")
    }

    func reload() {
        // No-op until #0094. The store's `reload()` button forwards here;
        // for the picker-only iteration the call is benign.
        onUpdate?(self)
    }
}
