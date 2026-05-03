import SwiftUI

struct RootView: View {
    @State private var bookmarks = FolderBookmarkService()
    @State private var store: IssueStore?

    var body: some View {
        Group {
            if let store {
                MainView(store: store) {
                    handleSwitchFolder()
                }
                .onChange(of: store.folderInvalidated) { _, invalid in
                    if invalid {
                        handleSwitchFolder()
                    }
                }
            } else {
                FolderPickerView(bookmarks: bookmarks) { url in
                    openFolder(url)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func openFolder(_ url: URL) {
        let store = IssueStore(folderURL: url)
        store.start()
        self.store = store
    }

    private func handleSwitchFolder() {
        store?.stop()
        store = nil
    }
}
