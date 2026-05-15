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
public final class AppCommandsController {
    public static let shared = AppCommandsController()

    /// User-configurable keyboard shortcut bindings (#0024). The
    /// `IssuesApp.commands { ... }` block reads the binding for each
    /// configurable action through this store; defaults match the literals
    /// shipped in #0008.
    public let shortcuts: ShortcutsStore = ShortcutsStore()

    /// Currently active tabs model. Set by `RootView` on appear.
    public var tabs: TabsModel?

    /// Currently active store (mirrors `tabs.activeTab`). Set by `MainView` on
    /// appear and on tab change so the menu doesn't have to re-walk the tabs
    /// list every time.
    public var activeStore: IssueStore?

    /// Bookmark service used by the picker scene to surface remembered
    /// folders and present the open panel. Set by `RootView` on appear.
    public var bookmarks: FolderBookmarkService?

    /// Remote-hosting glue (#0083). Set by `RootView` on appear so the
    /// Settings scene can bind to the same instance the main window holds.
    #if os(macOS)
    public var hostController: RemoteHostController?
    #endif

    /// Invoked when "New Tab" / `+` / Cmd+T fires (#0029). Set by
    /// `RootView.onAppear` to call `openWindow(id: "folderPicker")`. The
    /// controller can't read `@Environment(\.openWindow)` itself — only a
    /// `View` can — so we rely on a registered closure, same shape as
    /// `focusSearch`.
    public var openFolderPicker: (() -> Void)?

    /// Invoked when **File → Connect to Remote Host…** fires (#0091/#0096/
    /// #0097). Set by `RootView.onAppear` to call
    /// `openWindow(id: "remotePicker")`. Same indirection as
    /// `openFolderPicker` — the controller can't read
    /// `@Environment(\.openWindow)` directly.
    public var openRemoteFolderPicker: (() -> Void)?

    /// Invoked when **File → Manage Remote Subscriptions…** fires (#0098).
    /// Same indirection as `openRemoteFolderPicker`.
    public var openManageSubscriptions: (() -> Void)?

    /// Invoked with the currently selected issue when the user hits Enter or
    /// triggers an "open markdown" menu shortcut. Set by `MainView` so we can
    /// flip its `markdownSheetIssue` state. `nil` when no scene is mounted.
    public var openMarkdown: ((Issue) -> Void)?

    /// Invoked when Cmd+F fires. The search field doesn't exist yet (#0007),
    /// so this stays `nil` for now and the menu item no-ops. When #0007 lands,
    /// the search field's host view will set this to drive `@FocusState`.
    public var focusSearch: (() -> Void)?

    /// Invoked when Cmd+Shift+P (or **File → Show Command Palette…**) fires
    /// (#0055). Set by `MainView` so toggling the palette stays in view-local
    /// `@State`. Stays `nil` when no scene is mounted (e.g. empty-tab state),
    /// in which case the menu item no-ops.
    public var showCommandPalette: (() -> Void)?

    /// Invoked when File → Print… (Cmd+P) fires for the currently-selected
    /// issue (#0063). `nil` when no scene is mounted; menu item should
    /// also be disabled unless `activeStore?.selectedIssue != nil`.
    public var printSelectedIssue: (() -> Void)?

    /// Invoked when File → Generate Report… (Cmd+Shift+R) fires for the
    /// active tab (#0064). `nil` when no scene is mounted; menu item is
    /// disabled when `activeStore == nil`.
    public var generateReport: (() -> Void)?

    /// Routing intent deposited by the notification tap handler. Drained as
    /// soon as the tabs model is wired up — either immediately (warm app) or
    /// after `TabsModel.restore()` completes during a cold launch (#0026).
    public struct DeepLink {
        let tabID: UUID
        let issueID: String?   // nil for rollup notifications
    }

    public var pendingDeepLink: DeepLink?

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
    public func consumePendingDeepLinkIfPossible() {
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
            // Route through `requestReveal` so filters that would hide
            // the row surface the confirmation dialog (#0070) instead of
            // silently selecting an invisible issue.
            store.requestReveal(id: issueID)
        }
        pendingDeepLink = nil
    }

    // MARK: - Tab actions

    public func newTab() {
        // Cmd+T now opens the dedicated picker scene (#0029) instead of
        // presenting `NSOpenPanel` directly. The picker still falls
        // through to `NSOpenPanel` for "Add folder…", but it surfaces
        // remembered folders first.
        openFolderPicker?()
    }

    /// File → Connect to Remote Host… entry point (#0091/#0097). Opens
    /// the picker window if one isn't already up; the window is
    /// single-instance so duplicate clicks just bring it forward.
    public func connectToRemoteHost() {
        openRemoteFolderPicker?()
    }

    public func closeActiveTab() {
        guard let tabs, let id = tabs.activeTabID else { return }
        tabs.closeTab(id: id)
    }

    public func activateTab(at index: Int) {
        guard let tabs, index >= 0, index < tabs.tabs.count else { return }
        tabs.setActive(id: tabs.tabs[index].id)
    }

    public func nextTab() {
        guard let tabs, !tabs.tabs.isEmpty else { return }
        let n = tabs.tabs.count
        guard n > 1 else { return }
        let current = tabs.tabs.firstIndex(where: { $0.id == tabs.activeTabID }) ?? 0
        tabs.setActive(id: tabs.tabs[(current + 1) % n].id)
    }

    public func previousTab() {
        guard let tabs, !tabs.tabs.isEmpty else { return }
        let n = tabs.tabs.count
        guard n > 1 else { return }
        let current = tabs.tabs.firstIndex(where: { $0.id == tabs.activeTabID }) ?? 0
        tabs.setActive(id: tabs.tabs[(current - 1 + n) % n].id)
    }

    // MARK: - Active-store actions

    public func reloadActive() {
        activeStore?.reload()
    }

    public func setViewMode(_ mode: IssueStore.ViewMode) {
        activeStore?.viewMode = mode
    }

    public func openMarkdownForSelection() {
        guard let store = activeStore, let issue = store.selectedIssue else { return }
        openMarkdown?(issue)
    }

    public func triggerFocusSearch() {
        // TODO #0007: wired by the search field once it exists; no-op for now.
        focusSearch?()
    }

    /// Invoked by the **Show Command Palette…** menu item / Cmd+Shift+P. The
    /// closure is registered by the active `MainView`; if it's `nil` (no scene
    /// mounted yet) we silently no-op.
    public func triggerShowCommandPalette() {
        showCommandPalette?()
    }
}
