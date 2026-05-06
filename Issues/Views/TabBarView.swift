import AppKit
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
/// stored in `measuredWidths`. The phantom-slot threshold matches Safari:
/// the dragged chip swaps slots the **instant the cursor enters another
/// tab's `[anchorX, anchorX + width)` range**, not when the dragged chip's
/// center crosses anything. The cursor's bar-coord X is computed at each
/// `.onChanged` tick from `originalSlotAnchor + (startLocation.x +
/// translation.width)` and compared to cumulative slot anchors.
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
                .fixedSize(horizontal: true, vertical: false)
                // Drag gesture lives on this stable parent HStack — its
                // identity does not change when chip cells re-render, so
                // the gesture stays alive for the full drag and .onEnded
                // is reached on every release. simultaneousGesture lets it
                // coexist with each chip's own .onTapGesture for activate;
                // the min-distance gates which one wins (tap = no movement,
                // drag = ≥4pt movement).
                .simultaneousGesture(barDragGesture)

                if let dragged = draggedChip {
                    TabChipView(
                        store: dragged,
                        isActive: dragged.id == tabs.activeTabID,
                        hasUnseen: tabs.hasUnseenChanges[dragged.id] ?? false,
                        isOnlyTab: tabs.tabs.count <= 1,
                        onClose: { tabs.closeTab(id: dragged.id) },
                        onCloseOthers: {},
                        onRevealInFinder: {},
                        onReload: {}
                    )
                    .fixedSize(horizontal: true, vertical: false)
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

            TabBarAddButtonView()
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

    // Kept as a `@ViewBuilder` method rather than extracted into its own View
    // struct (#0036): it consumes six pieces of TabBarView's drag-state @State
    // (draggingID, originalSlot, phantomSlot, draggedWidth, measuredWidths,
    // plus tabs); extraction would require @Binding-plumbing that is harder
    // to follow than the inline switch.
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
                    isOnlyTab: tabs.tabs.count <= 1,
                    onClose: { tabs.closeTab(id: chip.id) },
                    onCloseOthers: {
                        for other in tabs.tabs where other.id != chip.id {
                            tabs.closeTab(id: other.id)
                        }
                    },
                    onRevealInFinder: {
                        NSWorkspace.shared.activateFileViewerSelecting([chip.folderURL])
                    },
                    onReload: { chip.reload() }
                )
                .fixedSize(horizontal: true, vertical: false)
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
                .accessibilityAddTraits(.isButton)
                // No per-chip drag gesture — the bar owns the drag now.
            }
        case .placeholder:
            Color.clear.frame(width: draggedWidth, height: 1)
        }
    }

    // MARK: - Drag gesture

    /// The single drag gesture for the whole bar. Lives on the inner
    /// `HStack` (a view whose identity does not change as cells re-render),
    /// so the gesture survives every cell update and `.onEnded` fires on
    /// every release. On the first `.onChanged` tick we hit-test
    /// `value.startLocation.x` against cumulative chip anchors to identify
    /// which chip the user grabbed.
    private var barDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingID == nil {
                    // First tick: identify the chip from the start location.
                    // `value.startLocation.x` is in the bar HStack's coord
                    // space (the gesture host) — same space as our
                    // cumulative anchor math, so the hit-test maps directly.
                    let startX = value.startLocation.x
                    guard let (idx, chip) = chipAtBarX(startX) else {
                        // Press began in an inter-chip gap or outside the
                        // bar — ignore until the cursor enters a chip.
                        return
                    }
                    // No animation here — we don't want the overlay's
                    // initial appearance to interpolate from the origin.
                    draggingID = chip.id
                    originalSlot = idx
                    phantomSlot = idx
                    placeholderID = UUID()
                    draggedWidth = measuredWidths[chip.id] ?? defaultTabWidth
                    originalSlotAnchor = computeAnchorX(for: idx)
                }
                dragXOffset = value.translation.width

                guard originalSlot != nil else { return }
                // Gesture is on the bar HStack now, so `value.location` is
                // already in bar coords — no anchor offset needed.
                let cursorBarX = value.location.x
                let newPhantom = computePhantomSlot(cursorBarX: cursorBarX)
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
                        // `reorderWithoutPersisting` uses
                        // `Array.move(fromOffsets:toOffset:)` semantics —
                        // for forward moves the destination is the index
                        // BEFORE which to insert in the original array,
                        // so passing `p` directly lands the chip one slot
                        // short of the user's drop. Adjust here.
                        let destination = (p > d) ? p + 1 : p
                        tabs.reorderWithoutPersisting(from: d, to: destination)
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

    /// Walk cumulative chip anchors and return the index + chip whose
    /// `[anchorX, anchorX + width)` range contains `x` (a bar-coord X,
    /// typically `DragGesture.Value.startLocation.x`). Returns `nil` if
    /// the press landed in an inter-chip gap or past the trailing chip —
    /// in that case the gesture's first tick is dropped.
    private func chipAtBarX(_ x: CGFloat) -> (Int, IssueStore)? {
        guard !tabs.tabs.isEmpty, x >= 0 else { return nil }
        var anchorX: CGFloat = 0
        for (idx, chip) in tabs.tabs.enumerated() {
            let w = measuredWidths[chip.id] ?? defaultTabWidth
            if x >= anchorX && x < anchorX + w {
                return (idx, chip)
            }
            anchorX += w + spacing
        }
        return nil
    }

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
    /// returns the index of the slot whose `[anchorX, anchorX + width)`
    /// range contains `cursorBarX`. This matches Safari's "tab swaps the
    /// instant the cursor enters another tab's slot" semantic.
    private func computePhantomSlot(cursorBarX: CGFloat) -> Int {
        guard !tabs.tabs.isEmpty else { return 0 }
        if cursorBarX < 0 { return 0 }
        var anchorX: CGFloat = 0
        for (idx, chip) in tabs.tabs.enumerated() {
            let w: CGFloat = (idx == originalSlot)
                ? draggedWidth
                : (measuredWidths[chip.id] ?? defaultTabWidth)
            if cursorBarX < anchorX + w {
                return idx
            }
            anchorX += w + spacing
        }
        return tabs.tabs.count - 1
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        TabBarView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        TabBarView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TabBarView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TabBarView(tabs: TabsModel(), bookmarks: FolderBookmarkService())
        .preferredColorScheme(.dark)
}
#endif
