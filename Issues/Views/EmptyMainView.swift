import SwiftUI
import IssuesCore

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

            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.appMuted)
                    Text("No folder open")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    // Dashed drop-zone hint (#0067) advertises that the
                    // surrounding window accepts a folder drag from Finder.
                    // The actual drop handler lives on the outer
                    // `folderDropTarget`; the accent border on hover drawn by
                    // that modifier supersedes this dashed style visually.
                    FolderDropHintView(
                        caption: "Drag an issues folder here to open it",
                        detail: "or click the + button \u{2014} \u{2318}T"
                    )
                    .frame(maxWidth: 360)
                }
                Button("Open Folder\u{2026}") {
                    openWindow(id: "folderPicker")
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Issues")
        .navigationSubtitle("")
        .background(Color.appBackground)
        .folderDropTarget { url in
            // Same drop flow as `MainView` — handles the case where the
            // main window is up but no tab is currently active (#0050).
            do {
                try bookmarks.remember(url: url)
            } catch {
                bookmarks.lastError = error.localizedDescription
                return
            }
            tabs.openTab(url: url)
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        EmptyMainView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        EmptyMainView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    EmptyMainView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    EmptyMainView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
        .preferredColorScheme(.dark)
}
#endif
