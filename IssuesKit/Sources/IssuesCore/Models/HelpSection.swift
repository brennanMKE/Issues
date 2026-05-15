import Foundation

/// One section in the in-app Help window. Backed by a single bundled
/// markdown file under `Help/` in the app bundle.
///
/// The order is hardcoded in `HelpCatalog.sections` — the help layout is
/// not user-reorderable. Sidebar order matches the numeric prefix of each
/// resource name purely as an authoring aid.
public struct HelpSection: Identifiable, Hashable, Sendable {
    /// Stable identifier used as the sidebar selection value. Matches the
    /// bundled filename stem (e.g. `01-overview`).
    public let id: String
    /// Human-readable label displayed in the sidebar.
    public let title: String
    /// Bundled resource name (filename stem without extension). Currently
    /// always equal to `id`; kept separate so a future rename of the
    /// sidebar identifier doesn't force a file rename.
    public let resourceName: String

    public init(id: String, title: String, resourceName: String) {
        self.id = id
        self.title = title
        self.resourceName = resourceName
    }
}
