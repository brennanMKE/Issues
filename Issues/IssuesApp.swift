import SwiftUI
import UserNotifications

@main
struct IssuesApp: App {
    /// Singleton menu controller so `.commands` items can drive view-model
    /// state. `RootView`/`MainView` populate its references on appear.
    @State private var commands = AppCommandsController.shared

    init() {
        // The notification delegate must outlive view recreations, so we wire
        // it to the singleton. Done in `init()` so the delegate is in place
        // before any system-delivered notification can arrive at launch.
        UNUserNotificationCenter.current().delegate = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
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
    }
}
