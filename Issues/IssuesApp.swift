import SwiftUI
import UserNotifications
import os.log

nonisolated private let appLogger = Logger(subsystem: Logging.subsystem, category: "IssuesApp")

@main
struct IssuesApp: App {
    /// Singleton menu controller so `.commands` items can drive view-model
    /// state. `RootView`/`MainView` populate its references on appear.
    @State private var commands = AppCommandsController.shared

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
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    commands.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Reload") {
                    commands.reloadActive()
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // View-mode shortcuts use Cmd+Opt+1..4 so they don't collide with
            // the tab Cmd+1..9 bindings below.
            CommandMenu("View") {
                Button("Swimlanes") {
                    commands.setViewMode(.swimlane)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Timeline") {
                    commands.setViewMode(.timeline)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("List") {
                    commands.setViewMode(.list)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("Recent") {
                    commands.setViewMode(.recent)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Divider()

                // Cmd+F focuses the search field. Search doesn't exist yet —
                // see #0007 — so this no-ops until that lands and sets
                // `focusSearch` on `AppCommandsController`.
                Button("Find") {
                    commands.triggerFocusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("Tabs") {
                Button("Show Previous Tab") {
                    commands.previousTab()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

                Button("Show Next Tab") {
                    commands.nextTab()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

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
    }
}

/// Help menu item. Lifted into its own `View` so the `@Environment`
/// property wrapper works — `CommandGroup`'s closure is a builder, not a
/// `View`, and can't read environment values directly.
private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Issues Help") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}
