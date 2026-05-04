import SwiftUI

struct MainView: View {
    @Bindable var store: IssueStore
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    @State private var markdownSheetIssue: Issue? = nil

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)
            TabBarView(tabs: tabs, bookmarks: bookmarks)
            StatsBarView(store: store, total: store.issues.count, counts: store.statusCounts)
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
        .preferredColorScheme(.dark)
        .sheet(item: $markdownSheetIssue) { issue in
            IssueMarkdownSheet(issue: issue)
        }
        .onAppear { registerCommandHandlers() }
        .onChange(of: store.id) { _, _ in registerCommandHandlers() }
    }

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.deselect() }
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
