import SwiftUI
import os.log

private let rootLogger = Logger(subsystem: Logging.subsystem, category: "RootView")

struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var bookmarks = FolderBookmarkService()
    @State private var tabs = TabsModel()
    @State private var hostController = RemoteHostController()

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
        // Keep the host's MultiFolderStore in sync with the tab list so
        // /v1/folders reflects what the user actually has open (#0083).
        .onChange(of: tabs.tabs.map(\.id)) { _, _ in
            hostController.setStores(tabs.tabs)
        }
        .onAppear {
            // Seed the host controller with the initial tab list at mount.
            hostController.setStores(tabs.tabs)

            // Register with the menu-bar command bridge. `MainView` updates
            // `activeStore` and `openMarkdown` when it mounts.
            AppCommandsController.shared.tabs = tabs
            AppCommandsController.shared.bookmarks = bookmarks
            AppCommandsController.shared.hostController = hostController
            // Hand the controller a closure it can call to open the picker
            // scene. Same indirection pattern as `focusSearch` — the
            // controller can't read `@Environment(\.openWindow)` itself,
            // so the view registers an opener on its behalf (#0029).
            AppCommandsController.shared.openFolderPicker = {
                openWindow(id: "folderPicker")
            }
            AppCommandsController.shared.openRemoteFolderPicker = {
                openWindow(id: "remotePicker")
            }
            AppCommandsController.shared.openManageSubscriptions = {
                openWindow(id: "manageSubscriptions")
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
        // `issues://open?path=<absolute-path>` from the standalone `issues`
        // CLI (#0119). LaunchServices delivers the URL whether the app was
        // already running or was launched by this dispatch.
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    /// Routes a single inbound `issues://` URL. Accepted shapes:
    /// `issues:///open?path=<absolute-path>` to open or activate a folder;
    /// `issues:///` (or any other path) to just bring the app forward.
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "issues" else {
            rootLogger.warning("onOpenURL: ignoring non-issues scheme \(url.scheme ?? "<none>", privacy: .public)")
            return
        }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            rootLogger.warning("onOpenURL: malformed url=\(url.absoluteString, privacy: .public)")
            return
        }
        // `/open` is the only verb in v1. No-op for everything else — the
        // app just comes forward via LaunchServices.
        guard comps.path == "/open" else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let path = comps.queryItems?.first(where: { $0.name == "path" })?.value, !path.isEmpty else {
            rootLogger.warning("onOpenURL: missing path query")
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let outcome = tabs.openOrActivate(folderPath: path, bookmarks: bookmarks)
        if outcome == .needsGrant {
            // Brand-new path — the sandbox needs an explicit grant. Open the
            // folder picker scene so the user can pick (or confirm) the
            // folder. Pre-targeting the panel at the requested path is a
            // follow-up; v1 surfaces the picker untargeted.
            openWindow(id: "folderPicker")
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        RootView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        RootView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    RootView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RootView()
        .preferredColorScheme(.dark)
}
#endif
