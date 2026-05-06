import SwiftUI

/// Spotlight / VS Code-style command palette (#0055).
///
/// Triggered by Cmd+Shift+P (or **File → Show Command Palette…**), this sheet
/// presents a single text field and a fuzzy-filtered list of:
/// - Every parsed issue in the active tab (id + title).
/// - View-mode actions ("Switch to Swimlanes/Timeline/List/Recent").
/// - Tab-switching actions ("Go to <repoName>") — for every tab other than the
///   currently-active one, in tab order.
///
/// Keyboard model:
/// - Up/down walks the result list (wrap-around).
/// - Enter invokes the highlighted command.
/// - Esc dismisses without invoking.
///
/// The palette closes on invoke, on Esc, or when the user clicks outside the
/// sheet (SwiftUI's standard sheet behavior). Switching tabs from a `.tab`
/// command dismisses immediately so the new tab is visible.
struct CommandPaletteView: View {
    @Bindable var store: IssueStore
    @Bindable var tabs: TabsModel

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            Divider().background(Color.appBorder)
            resultsList
        }
        .frame(width: 640, height: 420)
        .background(Color.appBackground)
        .onAppear {
            // Defer focus by one runloop tick so the sheet's own animation
            // settles before we hand focus to the field. Without this the
            // first keystrokes can land in the parent window on macOS.
            DispatchQueue.main.async { inputFocused = true }
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.return) {
            invokeSelected()
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appMuted)
                .font(.system(size: 14, weight: .medium))
            TextField("Search issues, view modes, tabs…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($inputFocused)
                .onChange(of: query) { _, _ in
                    // Reset highlight whenever the result set changes — the
                    // top hit is the natural "what you mean by Enter".
                    selectedIndex = 0
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    private var resultsList: some View {
        let results = filteredCommands()
        return Group {
            if results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                CommandPaletteRowView(
                                    command: command,
                                    isSelected: index == selectedIndex,
                                    onTap: {
                                        selectedIndex = index
                                        invokeSelected()
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        // Keep the highlighted row visible during keyboard
                        // walks. `scrollTo` no-ops when the row is already
                        // on-screen, so this is cheap to call on every move.
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No matches")
                .foregroundStyle(Color.appMuted)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Filtering

    /// Builds the candidate list and filters/sorts it by `query`. Empty input
    /// returns the default ordering — recent issues first, then view-mode
    /// actions, then tab actions — so the palette is useful before any
    /// keystroke.
    private func filteredCommands() -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = allCommands()
        if trimmed.isEmpty {
            return all
        }
        return all
            .compactMap { cmd -> (PaletteCommand, Int)? in
                guard let s = FuzzyMatch.score(query: trimmed, candidate: cmd.searchText) else {
                    return nil
                }
                return (cmd, s)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// Default-ordered command set. Issues come first by `modifiedAt` desc so
    /// the palette doubles as a "recents" affordance; view-mode and tab
    /// commands round it out below.
    private func allCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []
        let recentIssues = store.issues.sorted { $0.modifiedAt > $1.modifiedAt }
        for issue in recentIssues {
            commands.append(.issue(issue))
        }
        for mode in IssueStore.ViewMode.allCases where mode != store.viewMode {
            commands.append(.viewMode(mode))
        }
        for tab in tabs.tabs where tab.id != store.id {
            commands.append(.tab(tab))
        }
        return commands
    }

    // MARK: - Selection

    private func moveSelection(by delta: Int) {
        let count = filteredCommands().count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    private func invokeSelected() {
        let results = filteredCommands()
        guard !results.isEmpty,
              selectedIndex >= 0,
              selectedIndex < results.count else { return }
        let command = results[selectedIndex]
        invoke(command)
        dismiss()
    }

    private func invoke(_ command: PaletteCommand) {
        switch command {
        case .issue(let issue):
            // v1 behavior (per #0055): navigate to the issue but don't auto-
            // open the markdown sheet. The detail panel surfaces selection.
            store.selectedIssueID = issue.id
        case .viewMode(let mode):
            store.viewMode = mode
        case .tab(let target):
            tabs.setActive(id: target.id)
        }
    }
}

// MARK: - Command type

/// A single palette entry. Identifiable so SwiftUI can diff the result list
/// efficiently across input changes. Not `Hashable` — the `.tab` case
/// associates an `IssueStore` reference and we lean on the per-case `id`
/// strings for diffing instead.
enum PaletteCommand: Identifiable {
    case issue(Issue)
    case viewMode(IssueStore.ViewMode)
    case tab(IssueStore)

    var id: String {
        switch self {
        case .issue(let issue):    return "issue:\(issue.id)"
        case .viewMode(let mode):  return "view:\(mode.rawValue)"
        case .tab(let store):      return "tab:\(store.id.uuidString)"
        }
    }

    /// Primary text shown to the user and matched against by the fuzzy
    /// scorer. Includes the id for issues so "0042" is matchable.
    var displayText: String {
        switch self {
        case .issue(let issue):
            return "#\(issue.id) — \(issue.title)"
        case .viewMode(let mode):
            return "Switch to \(mode.displayName)"
        case .tab(let store):
            return "Go to \(store.repoName)"
        }
    }

    /// Secondary text (right-aligned in the row) used as a category label.
    var categoryText: String {
        switch self {
        case .issue:    return "Issue"
        case .viewMode: return "View"
        case .tab:      return "Tab"
        }
    }

    /// String fed to `FuzzyMatch.score`. Includes a richer pool than
    /// `displayText` for issues so module/status/description tokens also
    /// match.
    var searchText: String {
        switch self {
        case .issue(let issue):
            return "#\(issue.id) \(issue.title) \(issue.module) \(issue.description)"
        case .viewMode(let mode):
            return "Switch to \(mode.displayName) view mode"
        case .tab(let store):
            return "Go to \(store.repoName) tab"
        }
    }
}

#if DEBUG
#Preview("Light") {
    let store = PreviewSamples.makeStore()
    let tabs = TabsModel()
    return CommandPaletteView(store: store, tabs: tabs)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    let store = PreviewSamples.makeStore()
    let tabs = TabsModel()
    return CommandPaletteView(store: store, tabs: tabs)
        .preferredColorScheme(.dark)
}
#endif
