import SwiftUI
import IssuesCore

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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        FolderPickerSceneView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        FolderPickerSceneView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    FolderPickerSceneView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FolderPickerSceneView()
        .preferredColorScheme(.dark)
}
#endif
