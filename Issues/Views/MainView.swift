import SwiftUI

struct MainView: View {
    @Bindable var store: IssueStore
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    @State private var showingMarkdownSheet: Bool = false
    @State private var showingLintSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(tabs: tabs, bookmarks: bookmarks)
            StatsBarView(
                store: store,
                total: store.issues.count,
                counts: store.statusCounts,
                lintCount: store.lintFindings.count,
                onShowLint: { showingLintSheet = true }
            )
            ToolbarView(store: store)

            HStack(spacing: 0) {
                MainContentAreaView(store: store, showingMarkdownSheet: $showingMarkdownSheet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.selectedIssue != nil {
                    DetailPanelView(
                        issue: store.selectedIssue ?? placeholderIssue,
                        searchQuery: store.searchQuery,
                        onClose: { store.deselect() },
                        onOpenMarkdown: { issue in
                            store.selectedIssueID = issue.id
                            showingMarkdownSheet = true
                        }
                    )
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.selectedIssueID)

            if let error = store.loadError {
                MainErrorBannerView(message: error)
            }
        }
        .background(Color.appBackground)
        .folderDropTarget { url in
            // Dropping a folder onto the main window opens it as a new tab
            // (or activates an existing tab for the same path). Mirrors the
            // picker's bookmark step so the folder also lands in the
            // remembered list (#0050).
            do {
                try bookmarks.remember(url: url)
            } catch {
                bookmarks.lastError = error.localizedDescription
                return
            }
            tabs.openTab(url: url)
        }
        .sheet(isPresented: $showingMarkdownSheet) {
            IssueMarkdownSheet(store: store)
        }
        .sheet(isPresented: $showingLintSheet) {
            LintSheetView(findings: store.lintFindings)
        }
        .onAppear { registerCommandHandlers() }
        .onChange(of: store.id) { _, _ in registerCommandHandlers() }
        // Per-tab persistence (#0009): forward every user-driven UI change
        // on the active store to `TabsModel`, which debounces and writes to
        // UserDefaults. Each `.onChange` fires only when the bound value
        // actually changes; `saveTabStateIfChanged` additionally compares
        // the full snapshot before scheduling a flush, so duplicate fires
        // are cheap. Selection is included so reopening a tab restores the
        // detail panel on the issue the user was last looking at.
        .onChange(of: store.statusFilters) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.moduleFilter) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.platformFilter) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.searchQuery) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.viewMode) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.sortColumn) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.sortAscending) { _, _ in tabs.saveTabStateIfChanged(store) }
        .onChange(of: store.selectedIssueID) { _, _ in tabs.saveTabStateIfChanged(store) }
    }

    /// Wires `AppCommandsController` so menu-bar shortcuts can drive the
    /// active store. Re-runs when the active tab changes so the menu always
    /// targets the visible store.
    private func registerCommandHandlers() {
        AppCommandsController.shared.activeStore = store
        AppCommandsController.shared.openMarkdown = { issue in
            store.selectedIssueID = issue.id
            showingMarkdownSheet = true
        }
    }

    /// Fallback used only if the selected issue disappears between change
    /// observation and panel render — should not happen in practice.
    private var placeholderIssue: Issue {
        Issue(
            id: "----",
            title: "",
            status: .open,
            statusRaw: "open",
            module: "",
            platform: "",
            firstSeen: nil,
            firstSeenRaw: "",
            closed: nil,
            closedRaw: "",
            description: "",
            fileURL: store.folderURL,
            modifiedAt: Date()
        )
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        MainView(store: PreviewSamples.makeStore(), tabs: TabsModel(), bookmarks: FolderBookmarkService())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        MainView(store: PreviewSamples.makeStore(), tabs: TabsModel(), bookmarks: FolderBookmarkService())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    MainView(store: PreviewSamples.makeStore(), tabs: TabsModel(), bookmarks: FolderBookmarkService())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MainView(store: PreviewSamples.makeStore(), tabs: TabsModel(), bookmarks: FolderBookmarkService())
        .preferredColorScheme(.dark)
}
#endif
