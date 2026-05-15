import SwiftUI
import IssuesCore

struct FolderPickerRowView: View {
    let folder: RememberedFolder
    @Bindable var bookmarks: FolderBookmarkService
    let onSelect: (URL) -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        FolderPickerRowView(folder: PreviewSamples.rememberedFolder, bookmarks: FolderBookmarkService(), onSelect: { _ in })
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        FolderPickerRowView(folder: PreviewSamples.rememberedFolder, bookmarks: FolderBookmarkService(), onSelect: { _ in })
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    FolderPickerRowView(folder: PreviewSamples.rememberedFolder, bookmarks: FolderBookmarkService(), onSelect: { _ in })
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FolderPickerRowView(folder: PreviewSamples.rememberedFolder, bookmarks: FolderBookmarkService(), onSelect: { _ in })
        .padding()
        .preferredColorScheme(.dark)
}
#endif
