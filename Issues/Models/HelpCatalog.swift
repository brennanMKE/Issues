import Foundation

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
