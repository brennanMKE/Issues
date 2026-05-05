import SwiftUI

struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var bookmarks = FolderBookmarkService()
    @State private var tabs = TabsModel()

    var body: some View {
        Group {
            if let active = tabs.activeTab {
                MainView(store: active, tabs: tabs, bookmarks: bookmarks)
                    .onChange(of: active.folderInvalidated) { _, invalid in
                        if invalid {
                            tabs.closeTab(id: active.id)
                        }
                    }
            } else {
                // No active tab — render the empty-state surface from
                // `MainView` (#0029). The tab bar with the `+` button stays
                // visible above it so the user can still add tabs without
                // hunting for the empty-state button.
                EmptyMainView(tabs: tabs, bookmarks: bookmarks)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // Register with the menu-bar command bridge. `MainView` updates
            // `activeStore` and `openMarkdown` when it mounts.
            AppCommandsController.shared.tabs = tabs
            AppCommandsController.shared.bookmarks = bookmarks
            // Hand the controller a closure it can call to open the picker
            // scene. Same indirection pattern as `focusSearch` — the
            // controller can't read `@Environment(\.openWindow)` itself,
            // so the view registers an opener on its behalf (#0029).
            AppCommandsController.shared.openFolderPicker = {
                openWindow(id: "folderPicker")
            }
            // First-launch auto-open: if no remembered folders restored any
            // tabs, surface the picker so the user has a path forward
            // beyond an empty main window. This fires only on initial
            // appear; closing all tabs later does NOT auto-reopen the
            // picker (would be intrusive).
            if tabs.tabs.isEmpty {
                openWindow(id: "folderPicker")
            }
            // Drain any deep-link queued by a notification tap that arrived
            // during a cold launch (#0026). The tabs are now wired up and
            // `TabsModel.init()` already finished its synchronous restore.
            AppCommandsController.shared.consumePendingDeepLinkIfPossible()
        }
    }
}
