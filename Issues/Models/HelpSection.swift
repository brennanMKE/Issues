import Foundation

/// One section in the in-app Help window. Backed by a single bundled
/// markdown file under `Help/` in the app bundle.
///
/// The order is hardcoded in `HelpCatalog.sections` — the help layout is
/// not user-reorderable. Sidebar order matches the numeric prefix of each
/// resource name purely as an authoring aid.
struct HelpSection: Identifiable, Hashable {
    /// Stable identifier used as the sidebar selection value. Matches the
    /// bundled filename stem (e.g. `01-overview`).
    let id: String
    /// Human-readable label displayed in the sidebar.
    let title: String
    /// Bundled resource name (filename stem without extension). Currently
    /// always equal to `id`; kept separate so a future rename of the
    /// sidebar identifier doesn't force a file rename.
    let resourceName: String
}
