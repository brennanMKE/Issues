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
    /// back to a previously-viewed section avoids a second disk hit. The
    /// cache stores `Result` so failures are remembered too — and so the
    /// body stays a pure read of `contentCache[selection]` without any
    /// state mutation during render.
    @State private var contentCache: [String: Result<String, Error>] = [:]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(Color.appBackground)
        .task(id: selection) {
            await loadIfNeeded(selection)
        }
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
        Group {
            if let result = contentCache[selection] {
                switch result {
                case .success(let text):
                    successPane(text: text)
                case .failure(let error):
                    errorPane(error: error, sectionTitle: sectionTitle(for: selection))
                }
            } else {
                // First paint before `.task` has filled the cache. The
                // bundled files are tiny so this flashes briefly at most.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
            }
        }
        .navigationSplitViewColumnWidth(min: 480, ideal: 540)
    }

    @ViewBuilder
    private func successPane(text: String) -> some View {
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
    }

    @ViewBuilder
    private func errorPane(error: Error, sectionTitle: String) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load \(sectionTitle)")
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

    private var placeholder: some View {
        Text("Select a section")
            .font(.system(size: 13))
            .foregroundStyle(Color.appMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
    }

    private func sectionTitle(for id: HelpSection.ID) -> String {
        HelpCatalog.sections.first(where: { $0.id == id })?.title ?? id
    }

    // MARK: - Loading

    /// Fills `contentCache[id]` if it isn't already populated. Invoked
    /// from `.task(id: selection)` so the disk read happens outside view
    /// body evaluation and the cache write goes through normal `@State`
    /// mutation that SwiftUI invalidates correctly.
    private func loadIfNeeded(_ id: HelpSection.ID) async {
        if contentCache[id] != nil { return }
        guard let section = HelpCatalog.sections.first(where: { $0.id == id }) else { return }
        contentCache[id] = readMarkdown(for: section)
    }

    /// Pure read of the bundled markdown for `section`. No state access,
    /// no caching — `loadIfNeeded` owns the cache.
    private func readMarkdown(for section: HelpSection) -> Result<String, Error> {
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
