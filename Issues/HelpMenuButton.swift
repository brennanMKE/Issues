import SwiftUI

/// Help menu item. Lifted into its own `View` so the `@Environment`
/// property wrapper works — `CommandGroup`'s closure is a builder, not a
/// `View`, and can't read environment values directly.
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Issues Help") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}
