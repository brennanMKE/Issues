import SwiftUI
import AppKit
import UserNotifications
import os.log

nonisolated private let appLogger = Logger(subsystem: Logging.subsystem, category: "IssuesApp")

/// Terminates the app when the last window closes. Issues.app is a
/// single-main-window utility (#0074) — closing the main window should
/// exit the process rather than leave a stranded menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct IssuesApp: App {
    /// Singleton menu controller so `.commands` items can drive view-model
    /// state. `RootView`/`MainView` populate its references on appear.
    @State private var commands = AppCommandsController.shared

    /// AppKit delegate for behaviors SwiftUI doesn't surface as Scene
    /// modifiers — currently just terminate-after-last-window-closed.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        appLogger.notice("IssuesApp init \(NotificationService.processTag(), privacy: .public) args=\(CommandLine.arguments.joined(separator: " "), privacy: .public)")

        // The notification delegate must outlive view recreations, so we wire
        // it to the singleton. Done in `init()` so the delegate is in place
        // before any system-delivered notification can arrive at launch.
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        appLogger.debug("UNUserNotificationCenter delegate wired to NotificationService.shared")
    }

    var body: some Scene {
        // Single-instance `Window` (not `WindowGroup`) so that activating the
        // app from a notification tap re-uses the existing window instead of
        // spawning a second one. See #0026. The Help scene below is the only
        // additional window we ever expose.
        Window("Issues", id: "main") {
            RootView()
                .onAppear {
                    // Request notification authorization on first scene
                    // appear. The service guards on `hasRequestedAuthorization`
                    // so this only prompts once per process.
                    NotificationService.shared.requestAuthorization()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Suppress `File → New Window` (#0074). With single-window
            // `Window` scenes there's no second main window to spawn, and
            // hiding the menu item avoids a no-op entry in File.
            CommandGroup(replacing: .newItem) {}

            // Replace the standard Help menu with one that opens our own
            // `HelpView` window. `CommandGroup(replacing: .help)` keeps the
            // Cmd+? binding macOS users expect; the action just points at
            // the dedicated `id: "help"` window scene below.
            //
            // `@Environment(\.openWindow)` isn't available directly inside
            // `.commands { ... }` because the commands closure isn't a
            // `View`. Wrapping the button in a tiny `View` lets us read
            // the environment value where SwiftUI provides it.
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }

            // Tab management goes next to "New" in File. Cmd+T (New Tab),
            // Cmd+W (Close Tab), Cmd+R (Reload).
            //
            // Cmd+W note: SwiftUI's WindowGroup binds Cmd+W to "Close Window"
            // by default. Adding our own Cmd+W item in the File menu wins
            // over the implicit window-close binding when a window is key,
            // and the user can still close the window via the red traffic
            // light or Cmd+Shift+W (the standard "Close All").
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    commands.newTab()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .newTab))

                Button("Close Tab") {
                    commands.closeActiveTab()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .closeTab))

                Divider()

                // Open the remote-folder picker (#0091/#0096/#0097). No
                // keyboard shortcut today — discoverability via menu is
                // sufficient for the v1 surface.
                Button("Connect to Remote Host\u{2026}") {
                    commands.connectToRemoteHost()
                }

                // Manage open remote subscriptions (#0098). Close tabs,
                // forget hosts. The "Add folders" path falls through to
                // the picker above.
                Button("Manage Remote Subscriptions\u{2026}") {
                    commands.openManageSubscriptions?()
                }

                Divider()

                Button("Reload") {
                    commands.reloadActive()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .reload))

                Divider()

                // Command palette (#0055). The closure is registered by
                // `MainView`; if no scene is mounted it no-ops cleanly.
                Button("Show Command Palette\u{2026}") {
                    commands.triggerShowCommandPalette()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .commandPalette))

                Divider()

                // Print / Save as PDF for the currently-selected issue
                // (#0063). Disabled when nothing is selected — the user
                // explicitly picks a row first.
                Button("Print\u{2026}") {
                    commands.printSelectedIssue?()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(commands.activeStore?.selectedIssue == nil)

                Divider()

                // Generate Report (#0064). Disabled when no tab is
                // active. Writes into `<watched-folder>/reports/`.
                Button("Generate Report\u{2026}") {
                    commands.generateReport?()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(commands.activeStore == nil)
            }

            // View-mode shortcuts use Cmd+Opt+1..4 so they don't collide with
            // the tab Cmd+1..9 bindings below. All four are user-configurable
            // via Settings → Shortcuts (#0024).
            CommandMenu("View") {
                Button("Swimlanes") {
                    commands.setViewMode(.swimlane)
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .swimlanesView))

                Button("Timeline") {
                    commands.setViewMode(.timeline)
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .timelineView))

                Button("List") {
                    commands.setViewMode(.list)
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .listView))

                Button("Recent") {
                    commands.setViewMode(.recent)
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .recentView))

                Divider()

                // Cmd+F focuses the search field. Search doesn't exist yet —
                // see #0007 — so this no-ops until that lands and sets
                // `focusSearch` on `AppCommandsController`.
                Button("Find") {
                    commands.triggerFocusSearch()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .focusSearch))
            }

            CommandMenu("Tabs") {
                Button("Show Previous Tab") {
                    commands.previousTab()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .previousTab))

                Button("Show Next Tab") {
                    commands.nextTab()
                }
                .keyboardShortcut(commands.shortcuts.keyboardShortcut(for: .nextTab))

                Divider()

                // Cmd+1..9 jumps to tab N. Items past the current tab count
                // are still in the menu but no-op (see activateTab).
                ForEach(1...9, id: \.self) { n in
                    Button("Tab \(n)") {
                        commands.activateTab(at: n - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            }
        }

        // Dedicated Help window. Opt-in: only opens when the user picks
        // "Issues Help" from the Help menu (or hits Cmd+?). Lives in its
        // own window so the user can keep it next to the main window.
        Window("Issues Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 720, height: 800)
        .windowResizability(.contentMinSize)

        // Folder picker scene (#0029). Promoted out of the main window so
        // `RootView` no longer has to swap between picker and tabbed UI.
        // `Window` (vs. `WindowGroup`) gives us single-instance behavior:
        // mashing the tab bar's `+` (or Cmd+T) on an already-open picker
        // just brings it forward instead of spawning duplicates.
        Window("Open Folder", id: "folderPicker") {
            FolderPickerSceneView()
        }
        .defaultSize(width: 480, height: 520)
        .windowResizability(.contentMinSize)

        // Remote-folder picker (#0091/#0096/#0097). Single-instance like
        // the local folder picker so mashing the menu doesn't spawn
        // duplicates. The picker view owns its own multi-phase state.
        Window("Connect to Remote Host", id: "remotePicker") {
            RemoteFolderPickerView()
        }
        .defaultSize(width: 560, height: 540)
        .windowResizability(.contentMinSize)

        // Manage Remote Subscriptions sheet (#0098). Single-instance like
        // the picker; the sheet reads through TabsModel via the singleton
        // AppCommandsController.
        Window("Manage Remote Subscriptions", id: "manageSubscriptions") {
            ManageSubscriptionsSheetHost()
        }
        .defaultSize(width: 540, height: 440)
        .windowResizability(.contentMinSize)

        // Native Settings scene (#0024). SwiftUI auto-wires the
        // "Issues → Settings…" menu item with Cmd+, and gives us
        // single-instance preferences-window behavior for free.
        Settings {
            SettingsView()
        }
    }
}
