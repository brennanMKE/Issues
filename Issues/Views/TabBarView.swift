import SwiftUI

/// Horizontal Safari-style tab bar listing each open `IssueStore` as a chip.
/// Active tab uses the accent tint; inactive tabs use the card background.
/// Trailing "+" presents the folder open panel and adds a new tab.
///
/// Drag-to-reorder is intentionally out of scope for v1 — see issue #0002.
struct TabBarView: View {
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(tabs.tabs) { store in
                        TabChipView(
                            store: store,
                            isActive: store.id == tabs.activeTabID,
                            onSelect: { tabs.setActive(id: store.id) },
                            onClose: { tabs.closeTab(id: store.id) }
                        )
                    }
                    // TODO: drag to reorder
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            addButton
                .padding(.trailing, 12)
        }
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
    }

    private var addButton: some View {
        Button {
            if let url = bookmarks.presentOpenPanel() {
                tabs.openTab(url: url)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appText)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Open another folder in a new tab")
    }
}

private struct TabChipView: View {
    @Bindable var store: IssueStore
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? Color.appAccent : Color.appMuted)

            Text(store.repoName)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .truncationMode(.tail)

            // Reserve the close-button slot so the chip width doesn't jump on
            // hover. Hidden when not hovering and not active.
            ZStack {
                if isHovered || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.appMuted)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close tab")
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.appAccent.opacity(0.15) : Color.appBackgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.appAccent : Color.appBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            isHovered = hovering
        }
        .help(store.folderURL.path)
    }
}
