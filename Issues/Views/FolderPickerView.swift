import SwiftUI

struct FolderPickerView: View {
    @Bindable var bookmarks: FolderBookmarkService
    let onSelect: (URL) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Issues")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.appText)
                Text("Open a folder of issue markdown files.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appMuted)
            }
            .padding(.top, 32)

            if bookmarks.remembered.isEmpty {
                FolderPickerEmptyStateView()
            } else {
                FolderPickerRememberedListView(bookmarks: bookmarks, onSelect: onSelect)
            }

            Button {
                if let url = bookmarks.presentOpenPanel() {
                    onSelect(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                    Text("Add folder\u{2026}")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(Color.accentForeground)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.appAccent)
                )
            }
            .buttonStyle(.plain)

            if let error = bookmarks.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.statusWontfix)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
