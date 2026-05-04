import SwiftUI

/// Horizontal Safari-style tab bar listing each open `IssueStore` as a chip.
/// Active tab uses the accent tint; inactive tabs use the card background.
/// Trailing "+" presents the folder open panel and adds a new tab.
///
/// ## Reorder model — phantom-slot, ghost + placeholder (#0021, third pass)
///
/// Earlier passes either broke hit testing (`ZStack` + `.offset(x:)`) or
/// produced jitter / "ghosting" because the dragged chip's offset
/// compensation fought the HStack reflow whenever `tabs.tabs` was mutated
/// mid-drag. This pass removes mid-drag array mutation entirely:
///
/// - The HStack of cells does ALL layout for the non-dragged chips. No
///   per-chip `.offset(x:)` compensation.
/// - The dragged chip is rendered as a separate floating overlay in a
///   `ZStack` above the HStack. Its `offset.x` follows the cursor 1:1 — no
///   spring, no interpolation.
/// - At the dragged chip's original index, the HStack contains a "ghost"
///   cell (`Color.clear`) whose width animates between `draggedWidth` (when
///   the phantom slot equals the original slot) and `0` (when the phantom
///   slot has moved away).
/// - At the phantom slot index, when it differs from the original, the
///   HStack contains a `Color.clear` placeholder of width `draggedWidth`.
///   It moves through the displayItems array as the phantom slot updates.
/// - SwiftUI animates the HStack reflow as the placeholder moves and the
///   ghost shrinks/grows; neighbors slide naturally because their layout
///   positions changed.
/// - On `.onEnded` we call `tabs.reorderWithoutPersisting(from: d, to: p)`
///   once and then `persistTabs()`.
///
/// Variable chip widths are measured per-chip via `onGeometryChange` and
/// stored in `measuredWidths`; the phantom-slot threshold is computed by
/// walking those cumulative widths.
struct TabBarView: View {
    @Bindable var tabs: TabsModel
    @Bindable var bookmarks: FolderBookmarkService

    /// Gap between chips, matching the previous `LazyHStack(spacing: 6)`.
    private let spacing: CGFloat = 6
    /// Width used for chips whose natural size hasn't been measured yet
    /// (e.g. a tab created seconds ago whose `onGeometryChange` callback
    /// hasn't fired). Wide enough that the gesture math doesn't degenerate.
    private let defaultTabWidth: CGFloat = 200

    /// Per-chip natural width, captured via `onGeometryChange` while idle.
    /// Used to compute `draggedWidth`, the original-slot anchor, and the
    /// phantom-slot threshold during a drag.
    @State private var measuredWidths: [UUID: CGFloat] = [:]

    /// `id` of the chip currently being dragged. `nil` while idle.
    @State private var draggingID: UUID?
    /// Original index `d` of the dragged chip, captured at drag start.
    @State private var originalSlot: Int?
    /// Phantom slot `p` — where the dragged chip would land if released now.
    @State private var phantomSlot: Int?
    /// Stable identity for the placeholder DisplayItem so SwiftUI sees it
    /// MOVE through the displayItems array as `phantomSlot` changes,
    /// rather than vanishing-and-reappearing on each step. Refreshed at
    /// drag start to avoid colliding with any prior drag's placeholder.
    @State private var placeholderID: UUID = UUID()
    /// Live cursor translation — drives the floating overlay's `.offset.x`
    /// directly, no spring.
    @State private var dragXOffset: CGFloat = 0
    /// Width of the dragged chip, captured at drag start. Used for the
    /// floating overlay's frame, the ghost's max width, and the
    /// placeholder's width.
    @State private var draggedWidth: CGFloat = 0
    /// Leading-edge x of the dragged chip's original slot in the HStack
    /// (i.e. sum of preceding chip widths + spacings). The floating
    /// overlay's `.offset.x` is `originalSlotAnchor + dragXOffset`.
    @State private var originalSlotAnchor: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            // TODO #0021 auto-scroll: when the dragged chip nears the visible
            // bounds of an overflowing bar, programmatically scroll. For now
            // we let the bar overflow visually rather than wrap it in a
            // ScrollView (the math gets messier with scroll offsets and
            // Issues users rarely have enough tabs to overflow).
            ZStack(alignment: .topLeading) {
                HStack(spacing: spacing) {
                    ForEach(displayItems) { item in
                        cell(for: item)
                    }
                }

                if let dragged = draggedChip {
                    TabChipView(
                        store: dragged,
                        isActive: dragged.id == tabs.activeTabID,
                        hasUnseen: tabs.hasUnseenChanges[dragged.id] ?? false,
                        onClose: { tabs.closeTab(id: dragged.id) }
                    )
                    .frame(width: draggedWidth)
                    .scaleEffect(1.04)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .offset(x: originalSlotAnchor + dragXOffset, y: 0)
                    .zIndex(100)
                    .allowsHitTesting(false)
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

    // MARK: - Display items

    /// One item per HStack slot. While idle this is just `.tab` items in
    /// `tabs.tabs` order. During a drag we keep the dragged chip's `.tab`
    /// item in place (rendered as a transparent ghost) and additionally
    /// insert a `.placeholder` item at the phantom slot when it differs
    /// from the original — that placeholder is the visual drop zone.
    private var displayItems: [DisplayItem] {
        let plain = tabs.tabs.map { DisplayItem(id: AnyHashable($0.id), kind: .tab($0)) }
        guard let d = originalSlot, let p = phantomSlot, draggingID != nil, p != d else {
            return plain
        }
        var items = plain
        // For p > d: the ghost still sits at index d, so to land the
        // placeholder *after* the chip currently at index p we insert at p+1.
        // For p < d: insert directly at p so the placeholder sits *before*
        // the chip currently at p.
        let insertionIndex = (p > d) ? p + 1 : p
        items.insert(
            DisplayItem(id: AnyHashable(placeholderID), kind: .placeholder),
            at: insertionIndex
        )
        return items
    }

    /// The dragged `IssueStore`, looked up live so a tab close mid-drag
    /// (shouldn't happen but defensive) doesn't crash the overlay.
    private var draggedChip: IssueStore? {
        guard let id = draggingID else { return nil }
        return tabs.tabs.first { $0.id == id }
    }

    @ViewBuilder
    private func cell(for item: DisplayItem) -> some View {
        switch item.kind {
        case .tab(let chip):
            if chip.id == draggingID {
                // Ghost: the dragged chip's slot in the HStack collapses to
                // 0 width once the phantom slot moves away, so neighbors can
                // slide into the wake. While the phantom is still at the
                // original slot the ghost holds full width to mask the
                // overlay's takeoff.
                let ghostWidth: CGFloat = (phantomSlot == originalSlot) ? draggedWidth : 0
                Color.clear.frame(width: ghostWidth, height: 1)
            } else {
                TabChipView(
                    store: chip,
                    isActive: chip.id == tabs.activeTabID,
                    hasUnseen: tabs.hasUnseenChanges[chip.id] ?? false,
                    onClose: { tabs.closeTab(id: chip.id) }
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    // Only refresh measurements while idle — during a drag
                    // we want the captured `draggedWidth` and the anchor
                    // math to stay stable.
                    if draggingID == nil, newWidth > 0 {
                        measuredWidths[chip.id] = newWidth
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { tabs.setActive(id: chip.id) }
                .gesture(dragGesture(for: chip))
            }
        case .placeholder:
            Color.clear.frame(width: draggedWidth, height: 1)
        }
    }

    // MARK: - Drag gesture

    private func dragGesture(for chip: IssueStore) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingID == nil {
                    // First tick: capture all the static state for this drag.
                    // No animation here — we don't want the overlay's initial
                    // appearance to interpolate from the origin.
                    let idx = tabs.tabs.firstIndex { $0.id == chip.id } ?? 0
                    draggingID = chip.id
                    originalSlot = idx
                    phantomSlot = idx
                    placeholderID = UUID()
                    draggedWidth = measuredWidths[chip.id] ?? defaultTabWidth
                    originalSlotAnchor = computeAnchorX(for: idx)
                }
                dragXOffset = value.translation.width

                guard let d = originalSlot else { return }
                let newPhantom = computePhantomSlot(originalSlot: d, dragXOffset: dragXOffset)
                if newPhantom != phantomSlot {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        phantomSlot = newPhantom
                    }
                }
            }
            .onEnded { _ in
                guard let d = originalSlot, let p = phantomSlot else {
                    // Defensive: clear state if somehow we got here without
                    // a captured origin.
                    draggingID = nil
                    originalSlot = nil
                    phantomSlot = nil
                    dragXOffset = 0
                    return
                }
                // Single transaction: clear drag state (overlay disappears,
                // ghost width returns to natural) AND commit the array
                // reorder if the phantom moved. SwiftUI animates the HStack
                // reflow into the final order in one motion.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if p != d {
                        tabs.reorderWithoutPersisting(from: d, to: p)
                    }
                    draggingID = nil
                    originalSlot = nil
                    phantomSlot = nil
                    dragXOffset = 0
                }
                if p != d {
                    tabs.persistTabs()
                }
            }
    }

    // MARK: - Geometry helpers

    /// Leading-edge x of slot `index` in the natural HStack layout (i.e.
    /// before any drag started). Sum of preceding chips' measured widths
    /// plus spacings.
    private func computeAnchorX(for index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        var x: CGFloat = 0
        for i in 0..<index {
            guard i < tabs.tabs.count else { break }
            let id = tabs.tabs[i].id
            let w = measuredWidths[id] ?? defaultTabWidth
            x += w + spacing
        }
        return x
    }

    /// Walks the natural slot anchors (using each chip's measured width;
    /// at the original slot we use the dragged chip's captured width) and
    /// returns the index of the slot whose center the cursor has just
    /// crossed. This is the "past the halfway point of the next tab"
    /// rule generalized to variable widths.
    private func computePhantomSlot(originalSlot d: Int, dragXOffset: CGFloat) -> Int {
        guard !tabs.tabs.isEmpty else { return 0 }
        let cursorX = originalSlotAnchor + draggedWidth / 2 + dragXOffset
        var anchorX: CGFloat = 0
        for (idx, chip) in tabs.tabs.enumerated() {
            let w: CGFloat = (idx == d)
                ? draggedWidth
                : (measuredWidths[chip.id] ?? defaultTabWidth)
            let centerX = anchorX + w / 2
            if cursorX < centerX {
                return max(0, idx)
            }
            anchorX += w + spacing
        }
        return tabs.tabs.count - 1
    }

    // MARK: - Add button

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

// MARK: - Display item

/// One slot in the HStack while rendering. Either a real tab (rendered as
/// a `TabChipView`, or a transparent ghost when it's the one being
/// dragged) or the transparent placeholder that marks the phantom slot.
private struct DisplayItem: Identifiable {
    let id: AnyHashable
    let kind: Kind

    enum Kind {
        case tab(IssueStore)
        case placeholder
    }
}

// MARK: - Tab chip

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
