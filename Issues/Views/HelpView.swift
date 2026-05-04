import SwiftUI
import Textual

/// Help window root view. A two-pane `NavigationSplitView` with the
/// hardcoded `HelpCatalog.sections` as the sidebar and the selected
/// section's bundled markdown rendered via Textual's `StructuredText`
/// in the detail pane.
///
/// Intentionally has no dependency on `IssueStore` / `TabsModel`. The
/// help window is opened on demand via the Help menu and is fully
/// independent of the main window's state.
struct HelpView: View {
    @State private var selection: HelpSection.ID = HelpCatalog.sections.first!.id
    /// Lazy cache of section markdown keyed by `HelpSection.id`. Reads are
    /// cheap (a handful of small bundled files) but caching means flipping
    /// back to a previously-viewed section avoids a second disk hit.
    @State private var contentCache: [String: String] = [:]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(Color.appBackground)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(HelpCatalog.sections, selection: $selection) { section in
            Text(section.title)
                .font(.system(size: 13))
                .foregroundStyle(Color.appText)
                .tag(section.id)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let section = HelpCatalog.sections.first(where: { $0.id == selection }) {
            sectionView(for: section)
                .navigationSplitViewColumnWidth(min: 480, ideal: 540)
        } else {
            // Should be unreachable because `selection` is initialised to
            // the first section and is only ever set to a known id, but a
            // friendly fallback beats a blank pane.
            placeholder
                .navigationSplitViewColumnWidth(min: 480, ideal: 540)
        }
    }

    @ViewBuilder
    private func sectionView(for section: HelpSection) -> some View {
        switch loadMarkdown(for: section) {
        case .success(let text):
            ScrollView(.vertical) {
                StructuredText(
                    markdown: text,
                    baseURL: bundleHelpDirectory()
                )
                .textual.textSelection(.enabled)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.appBackground)
        case .failure(let error):
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load \(section.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.appBackground)
        }
    }

    private var placeholder: some View {
        Text("Select a section")
            .font(.system(size: 13))
            .foregroundStyle(Color.appMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
    }

    // MARK: - Loading

    /// Returns the markdown for the given section, populating
    /// `contentCache` on first read. Cached lookups don't touch disk.
    private func loadMarkdown(for section: HelpSection) -> Result<String, Error> {
        if let cached = contentCache[section.id] {
            return .success(cached)
        }
        guard let url = Bundle.main.url(
            forResource: section.resourceName,
            withExtension: "md",
            subdirectory: "Help"
        ) ?? Bundle.main.url(
            forResource: section.resourceName,
            withExtension: "md"
        ) else {
            return .failure(HelpLoadError.resourceMissing(section.resourceName))
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            // SwiftUI tolerates state mutation from a view's body during
            // a switch evaluation here because the cache write doesn't
            // change which branch we render — we still emit `.success`
            // for the same text on subsequent passes.
            contentCache[section.id] = text
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// Best-effort base URL for relative image references inside the help
    /// markdown. Returns the bundled `Help/` directory if it resolves, else
    /// the app bundle's resource URL, else nil. Images are out of scope
    /// for v1 but the `baseURL` keeps the door open.
    private func bundleHelpDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "Help", withExtension: nil) {
            return url
        }
        return Bundle.main.resourceURL
    }
}

private enum HelpLoadError: LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "The bundled file \(name).md is missing from the app's Help resources."
        }
    }
}
