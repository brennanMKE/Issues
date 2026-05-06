import SwiftUI

/// Split into its own view so SwiftUI can observe `bookmarks` directly via
/// `@Bindable`. `@Observable` services aren't observed when only read through
/// an outer optional binding.
struct KnownPathsList: View {
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
