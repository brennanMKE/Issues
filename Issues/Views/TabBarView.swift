import SwiftUI

/// Horizontal Safari-style tab bar listing each open `IssueStore` as a chip.
/// Active tab uses the accent tint; inactive tabs use the card background.
/// Trailing "+" presents the folder open panel and adds a new tab.
///
/// Chips support drag-to-reorder via SwiftUI's `.draggable` / `.dropDestination`
/// APIs; the new order is persisted by `TabsModel.reorder(from:to:)`. The `+`
/// add-tab button is intentionally not a drop target.
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
                            hasUnseen: tabs.hasUnseenChanges[store.id] ?? false,
                            onSelect: { tabs.setActive(id: store.id) },
                            onClose: { tabs.closeTab(id: store.id) }
                        )
                        .draggable(store.id.uuidString) {
                            // Faint copy of the chip as the drag preview.
                            TabChipView(
                                store: store,
                                isActive: store.id == tabs.activeTabID,
                                hasUnseen: tabs.hasUnseenChanges[store.id] ?? false,
                                onSelect: {},
                                onClose: {}
                            )
                            .opacity(0.6)
                        }
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            handleDrop(droppedIDs: droppedIDs, onto: store.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            addButton
                .padding(.trailing, 12)
        }
        // Horizontal ScrollView has no intrinsic vertical size and will
        // greedily consume whatever vertical space the parent VStack offers.
        // Pin the bar to chip-row height (≈22pt chip + 6pt vertical padding
        // top/bottom + a hair for the border).
        .frame(height: 36)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
    }

    /// Resolves the dropped chip's UUID, finds source/destination indices in
    /// `tabs.tabs`, and forwards to `TabsModel.reorder(from:to:)` (which uses
    /// the standard `Array.move(fromOffsets:toOffset:)` shape — `to` is the
    /// insertion offset *before* the source removal, so we pass `to + 1` when
    /// dropping onto a chip that comes after the dragged one).
    private func handleDrop(droppedIDs: [String], onto targetID: UUID) -> Bool {
        guard
            let raw = droppedIDs.first,
            let draggedID = UUID(uuidString: raw),
            let from = tabs.tabs.firstIndex(where: { $0.id == draggedID }),
            let to = tabs.tabs.firstIndex(where: { $0.id == targetID }),
            from != to
        else { return false }
        tabs.reorder(from: from, to: to > from ? to + 1 : to)
        return true
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
    let hasUnseen: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false

    /// Active tab never shows the dot, even if `hasUnseen` somehow lingers.
    private var showsUnseenDot: Bool { hasUnseen && !isActive }

    var body: some View {
        HStack(spacing: 6) {
            // Reserve the dot slot so the chip width doesn't jump when the
            // indicator appears/disappears.
            ZStack {
                if showsUnseenDot {
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
            }

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
        .help(helpText)
        .accessibilityLabel(accessibilityText)
    }

    private var helpText: String {
        if showsUnseenDot {
            return "\(store.folderURL.path) — Updated since last viewed"
        }
        return store.folderURL.path
    }

    private var accessibilityText: String {
        if showsUnseenDot {
            return "\(store.repoName), updated since last viewed"
        }
        return store.repoName
    }
}
