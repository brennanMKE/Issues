import Foundation
import Observation

/// Singleton bridge between menu-bar `.commands` items and the active scene's
/// view models. Menu items live outside the view hierarchy, so they can't
/// directly read `@Bindable` state from `RootView` / `MainView`. Rather than
/// thread `@FocusedSceneValue` through every focusable view (and fight macOS's
/// quirks about which subview happens to be focused when a menu fires), we keep
/// a tiny `@MainActor` observable that `RootView` writes into when a tab
/// activates, and that `IssuesApp.commands` reads when a shortcut fires.
///
/// The references are held strongly here but the lifetimes are short — when a
/// tab closes or the app restarts, `RootView` rewrites these. There is exactly
/// one window today, so a singleton is appropriate; if multi-window lands we
/// would migrate this to scene-scoped storage.
@MainActor
@Observable
final class AppCommandsController {
    static let shared = AppCommandsController()

    /// Currently active tabs model. Set by `RootView` on appear.
    var tabs: TabsModel?

    /// Currently active store (mirrors `tabs.activeTab`). Set by `MainView` on
    /// appear and on tab change so the menu doesn't have to re-walk the tabs
    /// list every time.
    var activeStore: IssueStore?

    /// Bookmark service used by the "New Tab" command to present the open
    /// panel. Set by `RootView` on appear.
    var bookmarks: FolderBookmarkService?

    /// Invoked with the currently selected issue when the user hits Enter or
    /// triggers an "open markdown" menu shortcut. Set by `MainView` so we can
    /// flip its `markdownSheetIssue` state. `nil` when no scene is mounted.
    var openMarkdown: ((Issue) -> Void)?

    /// Invoked when Cmd+F fires. The search field doesn't exist yet (#0007),
    /// so this stays `nil` for now and the menu item no-ops. When #0007 lands,
    /// the search field's host view will set this to drive `@FocusState`.
    var focusSearch: (() -> Void)?

    /// Routing intent deposited by the notification tap handler. Drained as
    /// soon as the tabs model is wired up — either immediately (warm app) or
    /// after `TabsModel.restore()` completes during a cold launch (#0026).
    struct DeepLink {
        let tabID: UUID
        let issueID: String?   // nil for rollup notifications
    }

    var pendingDeepLink: DeepLink?

    private init() {}

    // MARK: - Deep linking

    /// Drains `pendingDeepLink` if a matching tab is currently open. Safe to
    /// call from any of the wiring sites (notification handler, `RootView`'s
    /// `onAppear`, post-restore hook). No-ops when there's nothing to do.
    ///
    /// Edge cases:
    /// - No pending link → returns immediately.
    /// - Tabs not yet wired up (cold-launch race) → returns; the next caller
    ///   after restore will pick it up.
    /// - Tab id no longer present (folder removed, bookmark went stale and
    ///   #0012 dropped it) → silently clears the link rather than crashing.
    /// - Tab found but `issueID` doesn't match any current row → still
    ///   activates the tab; selection stays as-is.
    func consumePendingDeepLinkIfPossible() {
        guard let link = pendingDeepLink else { return }
        guard let tabs else { return }
        guard tabs.tabs.contains(where: { $0.id == link.tabID }) else {
            // Tab not present — drop the link so a later restore doesn't
            // re-fire on a stale id.
            pendingDeepLink = nil
            return
        }
        tabs.setActive(id: link.tabID)
        if let issueID = link.issueID,
           let store = tabs.tabs.first(where: { $0.id == link.tabID }) {
            store.selectedIssueID = issueID
        }
        pendingDeepLink = nil
    }

    // MARK: - Tab actions

    func newTab() {
        guard let bookmarks, let tabs else { return }
        if let url = bookmarks.presentOpenPanel() {
            tabs.openTab(url: url)
        }
    }

    func closeActiveTab() {
        guard let tabs, let id = tabs.activeTabID else { return }
        tabs.closeTab(id: id)
    }

    func activateTab(at index: Int) {
        guard let tabs, index >= 0, index < tabs.tabs.count else { return }
        tabs.setActive(id: tabs.tabs[index].id)
    }

    func nextTab() {
        guard let tabs, !tabs.tabs.isEmpty else { return }
        let n = tabs.tabs.count
        guard n > 1 else { return }
        let current = tabs.tabs.firstIndex(where: { $0.id == tabs.activeTabID }) ?? 0
        tabs.setActive(id: tabs.tabs[(current + 1) % n].id)
    }

    func previousTab() {
        guard let tabs, !tabs.tabs.isEmpty else { return }
        let n = tabs.tabs.count
        guard n > 1 else { return }
        let current = tabs.tabs.firstIndex(where: { $0.id == tabs.activeTabID }) ?? 0
        tabs.setActive(id: tabs.tabs[(current - 1 + n) % n].id)
    }

    // MARK: - Active-store actions

    func reloadActive() {
        activeStore?.reload()
    }

    func setViewMode(_ mode: IssueStore.ViewMode) {
        activeStore?.viewMode = mode
    }

    func openMarkdownForSelection() {
        guard let store = activeStore, let issue = store.selectedIssue else { return }
        openMarkdown?(issue)
    }

    func triggerFocusSearch() {
        // TODO #0007: wired by the search field once it exists; no-op for now.
        focusSearch?()
    }
}
