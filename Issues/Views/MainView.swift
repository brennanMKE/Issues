import SwiftUI

struct MainView: View {
    @Bindable var store: IssueStore
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    @State private var markdownSheetIssue: Issue? = nil
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
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.selectedIssue != nil {
                    DetailPanelView(
                        issue: store.selectedIssue ?? placeholderIssue,
                        onClose: { store.deselect() },
                        onOpenMarkdown: { markdownSheetIssue = $0 }
                    )
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.selectedIssueID)

            if let error = store.loadError {
                errorBanner(error)
            }
        }
        .background(Color.appBackground)
        .sheet(item: $markdownSheetIssue) { issue in
            IssueMarkdownSheet(issue: issue)
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

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.deselect() }
                .accessibilityHidden(true)
            switch store.viewMode {
            case .swimlane:
                SwimlaneView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            case .timeline:
                TimelineView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            case .list:
                ListView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            case .recent:
                RecentView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            store.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            store.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            if let issue = store.selectedIssue {
                markdownSheetIssue = issue
                return .handled
            }
            return .ignored
        }
    }

    /// Wires `AppCommandsController` so menu-bar shortcuts can drive the
    /// active store. Re-runs when the active tab changes so the menu always
    /// targets the visible store.
    private func registerCommandHandlers() {
        AppCommandsController.shared.activeStore = store
        AppCommandsController.shared.openMarkdown = { issue in
            markdownSheetIssue = issue
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusOpen)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.appText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.appBackgroundCard)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appBorder).frame(height: 1)
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

/// Empty-state surface shown when no tab is active (#0029). Replaces the
/// old behavior where `RootView` swapped `FolderPickerView` into the main
/// window; the picker now lives in its own `Window` scene. The tab bar is
/// still rendered so the user can hit `+` to bring up the picker without
/// hunting for the central button.
struct EmptyMainView: View {
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(tabs: tabs, bookmarks: bookmarks)

            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.appMuted)
                Text("No folder open")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text("Click the + button or press \u{2318}T to open an issues folder.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                    .multilineTextAlignment(.center)
                Button("Open Folder\u{2026}") {
                    openWindow(id: "folderPicker")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBackground)
    }
}

/// Wrapper used by the dedicated `Window("Open Folder", id: "folderPicker")`
/// scene. The picker scene has its own SwiftUI environment, so it pulls the
/// shared `FolderBookmarkService` and `TabsModel` from `AppCommandsController`
/// rather than threading bindings across windows. After a successful
/// selection it activates the main window and dismisses itself (#0029).
struct FolderPickerSceneView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// Fallback bookmarks instance used only if the scene somehow renders
    /// before `RootView.onAppear` has registered the shared one. Reads the
    /// same `UserDefaults` key, so the remembered list is still correct.
    @State private var fallbackBookmarks = FolderBookmarkService()

    var body: some View {
        FolderPickerView(bookmarks: AppCommandsController.shared.bookmarks ?? fallbackBookmarks) { url in
            AppCommandsController.shared.tabs?.openTab(url: url)
            // No-op if the main window is already up; if the user had
            // closed it, this brings the new tab somewhere visible.
            openWindow(id: "main")
            dismissWindow(id: "folderPicker")
        }
    }
}
