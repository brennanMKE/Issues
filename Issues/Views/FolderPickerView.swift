import SwiftUI

struct FolderPickerView: View {
    @Bindable var bookmarks: FolderBookmarkService
    let onSelect: (URL) -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

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
                emptyState
            } else {
                rememberedList
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
                .foregroundStyle(Color.white)
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(Color.appMuted)
            Text("No remembered folders yet.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.vertical, 12)
    }

    private var rememberedList: some View {
        VStack(spacing: 6) {
            Text("Recent")
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Color.appMuted)
                .frame(maxWidth: 360, alignment: .leading)
            ForEach(bookmarks.remembered) { folder in
                folderRow(folder)
            }
        }
        .frame(maxWidth: 360)
    }

    private func folderRow(_ folder: RememberedFolder) -> some View {
        Button {
            do {
                let url = try bookmarks.resolve(folder)
                onSelect(url)
            } catch {
                bookmarks.lastError = error.localizedDescription
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.appAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text(folder.displayParent)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(Self.dateFormatter.string(from: folder.lastUsed))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appMuted)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Forget") {
                bookmarks.forget(folder)
            }
        }
    }
}
