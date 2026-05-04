import SwiftUI

struct RootView: View {
    @State private var bookmarks = FolderBookmarkService()
    @State private var tabs = TabsModel()

    var body: some View {
        Group {
            if tabs.tabs.isEmpty {
                FolderPickerView(bookmarks: bookmarks) { url in
                    tabs.openTab(url: url)
                }
            } else if let active = tabs.activeTab {
                MainView(store: active, tabs: tabs, bookmarks: bookmarks)
                    .onChange(of: active.folderInvalidated) { _, invalid in
                        if invalid {
                            tabs.closeTab(id: active.id)
                        }
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // Register with the menu-bar command bridge. `MainView` updates
            // `activeStore` and `openMarkdown` when it mounts.
            AppCommandsController.shared.tabs = tabs
            AppCommandsController.shared.bookmarks = bookmarks
            // Drain any deep-link queued by a notification tap that arrived
            // during a cold launch (#0026). The tabs are now wired up and
            // `TabsModel.init()` already finished its synchronous restore.
            AppCommandsController.shared.consumePendingDeepLinkIfPossible()
        }
    }
}
