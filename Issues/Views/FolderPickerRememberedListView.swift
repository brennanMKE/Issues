import SwiftUI

struct FolderPickerRememberedListView: View {
    @Bindable var bookmarks: FolderBookmarkService
    let onSelect: (URL) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Recent")
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Color.appMuted)
                .frame(maxWidth: 360, alignment: .leading)
            ForEach(bookmarks.remembered) { folder in
                FolderPickerRowView(folder: folder, bookmarks: bookmarks, onSelect: onSelect)
            }
        }
        .frame(maxWidth: 360)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        FolderPickerRememberedListView(bookmarks: FolderBookmarkService(), onSelect: { _ in })
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        FolderPickerRememberedListView(bookmarks: FolderBookmarkService(), onSelect: { _ in })
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    FolderPickerRememberedListView(bookmarks: FolderBookmarkService(), onSelect: { _ in })
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FolderPickerRememberedListView(bookmarks: FolderBookmarkService(), onSelect: { _ in })
        .padding()
        .preferredColorScheme(.dark)
}
#endif
