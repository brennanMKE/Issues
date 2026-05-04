import SwiftUI

/// Horizontal Safari-style tab bar listing each open `IssueStore` as a chip.
/// Active tab uses the accent tint; inactive tabs use the card background.
/// Trailing "+" presents the folder open panel and adds a new tab.
///
/// Tabs are laid out in a regular `HStack(spacing: tabSpacing)` so each chip
/// occupies its natural layout slot — hit testing matches what's drawn. Each
/// chip has a fixed width (so the array-index <-> visual-slot mapping is
/// trivial); long repo names truncate. While a chip is being dragged we apply
/// `.offset(x:)` *only* to that chip, compensating for any in-drag array
/// reorders so the dragged chip stays pinned under the cursor:
/// `visualOffset = (originalIndex - currentIdx) * stride + dragXOffset`.
/// Neighbors render at their natural HStack positions and animate via
/// `.animation(value: currentIdx)` when their slots change. On each
/// `onChanged` we recompute `slotsCrossed` and mutate `TabsModel.tabs` (via
/// `reorderWithoutPersisting`) when the dragged chip lands on a new slot.
/// Persistence is flushed once, on `onEnded`, to avoid UserDefaults thrash.
/// (#0021 — replaces the `.draggable`/`.dropDestination` flow from #0011.)
struct TabBarView: View {
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    /// Fixed chip width so the index-to-slot math is trivial. Wide enough for
    /// most repo names; the chip truncates with an ellipsis past this.
    private let tabWidth: CGFloat = 200
    /// Gap between chips, matching the previous `LazyHStack(spacing: 6)`.
    private let tabSpacing: CGFloat = 6
    private var tabStride: CGFloat { tabWidth + tabSpacing }

    @State private var draggingID: UUID?
    @State private var originalIndex: Int?
    @State private var dragXOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            // TODO #0021 auto-scroll: when the dragged chip nears the visible
            // bounds of an overflowing bar, programmatically scroll. For now
            // we let the bar overflow visually rather than wrap it in a
            // ScrollView (the math gets messier with scroll offsets and
            // Issues users rarely have enough tabs to overflow).
            HStack(spacing: tabSpacing) {
                ForEach(tabs.tabs) { store in
                    let isDragging = draggingID == store.id
                    let currentIdx = tabs.tabs.firstIndex(where: { $0.id == store.id }) ?? 0
                    // While dragging, the chip sits at `currentIdx`'s slot via
                    // HStack layout. We want it visually at `originalIndex`'s
                    // slot plus the live drag translation, so the chip stays
                    // pinned under the cursor as neighbors slide around it.
                    let visualOffset: CGFloat = isDragging
                        ? CGFloat((originalIndex ?? currentIdx) - currentIdx) * tabStride + dragXOffset
                        : 0

                    TabChipView(
                        store: store,
                        isActive: store.id == tabs.activeTabID,
                        hasUnseen: tabs.hasUnseenChanges[store.id] ?? false,
                        onClose: { tabs.closeTab(id: store.id) }
                    )
                    .frame(width: tabWidth)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: 14, y: 8)
                    .offset(x: visualOffset)
                    .zIndex(isDragging ? 1 : 0)
                    // Slot-change spring fires only on *neighbors* — animating
                    // the dragged chip's compensated offset between old/new
                    // slots fights the cursor (which drives `dragXOffset`
                    // directly) and reads as jitter. See #0021 follow-up.
                    .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.78), value: currentIdx)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDragging)
                    .contentShape(Rectangle())
                    .onTapGesture { tabs.setActive(id: store.id) }
                    .gesture(dragGesture(for: store))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            addButton
                .padding(.trailing, 12)

            Spacer(minLength: 0)
        }
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

    private func dragGesture(for store: IssueStore) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingID == nil {
                    draggingID = store.id
                    originalIndex = tabs.tabs.firstIndex(where: { $0.id == store.id })
                }
                guard let origIdx = originalIndex else { return }

                dragXOffset = value.translation.width

                let crossed = slotsCrossed(dragOffset: dragXOffset, stride: tabStride)
                let target = targetIndex(
                    originalIndex: origIdx,
                    slotsCrossed: crossed,
                    count: tabs.tabs.count
                )
                let currentIdx = tabs.tabs.firstIndex(where: { $0.id == store.id }) ?? origIdx

                if target != currentIdx {
                    // Bridge to `TabsModel`'s move-offsets-shaped API: when
                    // moving forward, the destination offset is one past the
                    // final index because the source removal shifts later
                    // indices left by one.
                    let destination = target > currentIdx ? target + 1 : target
                    // Suppress any implicit animation on the array mutation —
                    // we drive the dragged chip's position from the cursor and
                    // let neighbors animate via their own `.animation(value:)`.
                    withTransaction(Transaction(animation: nil)) {
                        tabs.reorderWithoutPersisting(from: currentIdx, to: destination)
                    }
                }
            }
            .onEnded { _ in
                let mutated = originalIndex != nil
                draggingID = nil
                originalIndex = nil
                dragXOffset = 0
                if mutated {
                    // Single UserDefaults write per drag — see TabsModel.
                    tabs.persistTabs()
                }
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

// MARK: - Reorder math (pure, free functions for unit-testability)

/// How many tab-slots the dragged chip's center has crossed, rounded to the
/// nearest integer. Positive means rightward, negative means leftward.
/// Free function (not nested) so the test target can call it directly.
func slotsCrossed(dragOffset: CGFloat, stride: CGFloat) -> Int {
    guard stride > 0 else { return 0 }
    return Int((dragOffset / stride).rounded())
}

/// Resolves the dragged chip's current target slot in `[0, count - 1]` given
/// where it started and how many slots it has crossed. Clamps out-of-range
/// drags to the ends so a hard flick past the bar's edge parks the chip at
/// the first/last slot rather than no-op'ing.
func targetIndex(originalIndex: Int, slotsCrossed: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return max(0, min(count - 1, originalIndex + slotsCrossed))
}

private struct TabChipView: View {
    @Bindable var store: IssueStore
    let isActive: Bool
    let hasUnseen: Bool
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

            Spacer(minLength: 0)

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
