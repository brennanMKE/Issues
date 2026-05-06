import SwiftUI

/// General settings pane. Currently surfaces the Known Paths list — every
/// folder the app has remembered via `FolderBookmarkService` — so the user can
/// prune entries without right-clicking the picker.
///
/// The Settings scene doesn't inherit the main window's view environment, so
/// we reach for the bookmark service through `AppCommandsController.shared`,
/// which `RootView` populates on appear. Removing a folder here updates the
/// same instance the main window's picker uses; tabs already open against a
/// removed folder keep their session — only the persisted list shrinks.
struct GeneralSettingsView: View {
    @State private var commands = AppCommandsController.shared

    var body: some View {
        Form {
            Section("Known Paths") {
                if let bookmarks = commands.bookmarks {
                    KnownPathsList(bookmarks: bookmarks)
                } else {
                    // Reachable only if the user opens Settings before the
                    // main window has finished its first appearance — vanishingly
                    // rare in practice, but worth a real message rather than
                    // an empty section.
                    Text("Folder list isn\u{2019}t ready yet. Open the main window first.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralSettingsView()
}
