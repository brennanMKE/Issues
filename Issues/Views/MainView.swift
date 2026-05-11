import SwiftUI

struct MainView: View {
    @Bindable var store: IssueStore
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    @State private var showingMarkdownSheet: Bool = false
    @State private var showingLintSheet: Bool = false
    /// Drives the Cmd+Shift+P command palette sheet (#0055). View-local so the
    /// palette only ever exists for the active scene; menu fires route through
    /// `AppCommandsController.showCommandPalette` which we register on appear.
    @State private var showingCommandPalette: Bool = false

    /// Persisted detail-panel width (#0069). Default 360pt matches the pre-fix
    /// layout. Clamped on read against the live window width via
    /// `clampedPanelWidth(for:)` so a previously-saved value larger than the
    /// current window's `width / 3` cap is honored as the intent but never
    /// rendered larger than the cap.
    @AppStorage("detailPanelWidth") private var detailPanelWidth: Double = 360

    /// Smallest width that still leaves room for the metadata grid plus a
    /// 240pt-wide attachment thumbnail with breathing room. Matches the
    /// behavior contract in `project-issues/0069.md`.
    private static let minDetailPanelWidth: CGFloat = 280

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

            // GeometryReader gives us the live width of the content+panel
            // strip so the panel's max-width clamp (`width / 3` per #0069)
            // tracks window resizes in real time. Wrapping just this HStack
            // (not the whole MainView) keeps tabs/stats/toolbar out of the
            // GeometryReader's layout pass.
            GeometryReader { geometry in
                let panelWidth = clampedPanelWidth(for: geometry.size.width)
                HStack(spacing: 0) {
                    MainContentAreaView(store: store, showingMarkdownSheet: $showingMarkdownSheet)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if store.selectedIssue != nil {
                        // Resize handle sits on the panel's leading edge
                        // (#0069). It's a 6pt invisible strip that flips the
                        // cursor to horizontal-resize on hover; dragging
                        // mutates `detailPanelWidth` which flows back through
                        // `clampedPanelWidth(for:)` on the next layout pass.
                        DetailPanelResizeHandle(
                            currentWidth: panelWidth,
                            onResize: { proposed in
                                detailPanelWidth = Double(
                                    clampedPanelWidth(
                                        proposed,
                                        windowWidth: geometry.size.width
                                    )
                                )
                            }
                        )

                        DetailPanelView(
                            issue: store.selectedIssue ?? placeholderIssue,
                            searchQuery: store.searchQuery,
                            onClose: { store.deselect() },
                            onOpenMarkdown: { issue in
                                store.selectedIssueID = issue.id
                                showingMarkdownSheet = true
                            },
                            // Cross-reference clicks (#0054) — swap the panel's
                            // selection in place. If the referenced id isn't in
                            // the current folder, leave selection untouched so
                            // the click no-ops cleanly.
                            onOpenIssue: { id in
                                guard store.issues.contains(where: { $0.id == id }) else { return }
                                store.selectedIssueID = id
                            }
                        )
                        // Pinning the panel's width here is the core of #0069:
                        // without `.frame(width:)`, the ScrollView reports the
                        // intrinsic width of its content and the panel jiggles
                        // as the user navigates between issues with different
                        // body lengths or thumbnail widths.
                        .frame(width: panelWidth)
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: store.selectedIssueID)
            }

            if let error = store.loadError {
                MainErrorBannerView(message: error)
            }
        }
        .navigationTitle(store.displayName)
        .navigationSubtitle(windowSubtitle)
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
        .sheet(isPresented: $showingCommandPalette) {
            CommandPaletteView(store: store, tabs: tabs)
        }
        .confirmationDialog(
            revealDialogTitle,
            isPresented: revealDialogPresented,
            titleVisibility: .visible,
            presenting: store.pendingReveal
        ) { issue in
            Button("Reveal Issue") { store.revealIssue(issue) }
            Button("Cancel", role: .cancel) { store.cancelReveal() }
        } message: { issue in
            Text(revealDialogMessage(for: issue))
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
        AppCommandsController.shared.showCommandPalette = {
            showingCommandPalette = true
        }
    }

    /// Window-chrome subtitle: a `"\(filtered) of \(total)"` count when a
    /// filter or search narrows the list, or a plain `"\(total) issues"`
    /// (singular `"1 issue"`) when nothing is filtered. Drives
    /// `.navigationSubtitle` so the title bar carries useful context across
    /// tabs (#0052).
    private var windowSubtitle: String {
        let filtered = store.filteredIssues.count
        let total = store.issues.count
        if filtered == total {
            return total == 1 ? "1 issue" : "\(total) issues"
        }
        return "\(filtered) of \(total)"
    }

    // MARK: - Notification reveal dialog (#0070)

    private var revealDialogPresented: Binding<Bool> {
        Binding(
            get: { store.pendingReveal != nil },
            set: { isPresented in
                if !isPresented { store.cancelReveal() }
            }
        )
    }

    private var revealDialogTitle: String {
        guard let issue = store.pendingReveal else { return "" }
        return "Reveal #\(issue.id) — \(issue.title)?"
    }

    private func revealDialogMessage(for issue: Issue) -> String {
        var lines: [String] = []
        lines.append("Status: \(issue.status.displayName) · Module: \(issue.module.isEmpty ? "—" : issue.module) · Platform: \(issue.platform.isEmpty ? "—" : issue.platform)")
        let firstParagraph = issue.description
            .split(separator: "\n\n", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let trimmed = firstParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("")
            // Cap the snippet so the dialog stays compact.
            if trimmed.count > 300 {
                lines.append(String(trimmed.prefix(300)) + "…")
            } else {
                lines.append(trimmed)
            }
        }
        lines.append("")
        lines.append("Revealing switches this tab to List and clears the filters that hide this issue.")
        return lines.joined(separator: "\n")
    }

    /// Clamps the persisted `detailPanelWidth` against `[minDetailPanelWidth,
    /// windowWidth / 3]` for the current window width (#0069). Called on
    /// every layout pass so the panel shrinks live when the window shrinks
    /// past `currentPanelWidth × 3`. The persisted value itself is left
    /// untouched — the user's intent is preserved and re-honored as soon as
    /// the window grows back.
    private func clampedPanelWidth(for windowWidth: CGFloat) -> CGFloat {
        clampedPanelWidth(CGFloat(detailPanelWidth), windowWidth: windowWidth)
    }

    /// Pure clamp helper shared by the layout path and the resize-handle
    /// callback. Falls back to `minDetailPanelWidth` if the window is so
    /// narrow that `width / 3` would go below the floor — the panel still
    /// renders at the floor in that case rather than collapsing.
    private func clampedPanelWidth(_ proposed: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let maxWidth = max(MainView.minDetailPanelWidth, windowWidth / 3)
        return min(max(proposed, MainView.minDetailPanelWidth), maxWidth)
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
            modifiedAt: Date(),
            hasAttachments: false
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
