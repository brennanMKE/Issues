import SwiftUI

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
