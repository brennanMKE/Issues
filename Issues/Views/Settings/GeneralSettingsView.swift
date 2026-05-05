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

/// Split into its own view so SwiftUI can observe `bookmarks` directly via
/// `@Bindable`. `@Observable` services aren't observed when only read through
/// an outer optional binding.
private struct KnownPathsList: View {
    @Bindable var bookmarks: FolderBookmarkService

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if bookmarks.remembered.isEmpty {
            HStack {
                Spacer()
                Text("No remembered folders. Open one from the tab bar\u{2019}s + button.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            ForEach(bookmarks.remembered) { folder in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.displayName)
                            .font(.body)
                        Text(folder.displayParent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Last used \(Self.dateFormatter.string(from: folder.lastUsed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        bookmarks.forget(folder)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

#Preview {
    GeneralSettingsView()
}
