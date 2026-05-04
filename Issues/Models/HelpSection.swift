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

/// Static catalog of Help sections. The order here defines the order of
/// the sidebar in `HelpView`.
enum HelpCatalog {
    static let sections: [HelpSection] = [
        .init(id: "01-overview",            title: "Overview",            resourceName: "01-overview"),
        .init(id: "02-tabs",                title: "Tabs",                resourceName: "02-tabs"),
        .init(id: "03-keyboard-shortcuts",  title: "Keyboard Shortcuts",  resourceName: "03-keyboard-shortcuts"),
        .init(id: "04-search-and-filter",   title: "Search and Filter",   resourceName: "04-search-and-filter"),
        .init(id: "05-viewing-an-issue",    title: "Viewing an Issue",    resourceName: "05-viewing-an-issue"),
        .init(id: "06-lint-findings",       title: "Lint Findings",       resourceName: "06-lint-findings"),
        .init(id: "07-ai-integration",      title: "AI Integration",      resourceName: "07-ai-integration"),
        .init(id: "08-privacy-and-sandbox", title: "Privacy and Sandbox", resourceName: "08-privacy-and-sandbox"),
    ]
}
