# 0021 — Simplify by replacing custom drag with `visfitness/reorderable`

## Context for Claude Code

This is a follow-up on issue #0021 (Safari-style tab reordering). The custom implementation has gone through five commits (`40e25ab` → `8271bbd` → `2223974` → `4d58c22` → `e404b4a`) and is still broken — drag is choppy, drop doesn't reliably cancel, clicks leak to close buttons, and state gets stuck after `.onEnded` fails to fire.

The team's own diagnosis (in `0021.md`) is correct: the gesture's host view is being replaced mid-drag (chip → `Color.clear`), which churns the gesture and prevents `.onEnded` from running reliably. The "current plan to fix" (move gesture to a stable parent, always render `TabChipView`) is structurally right.

**Rather than continue building this in-house, adopt `visfitness/reorderable`** — a maintained SwiftUI package that already implements the structural fix the plan describes, and has been hardened against the SwiftUI gesture edge cases that have caused the iteration loop on this ticket.

## Why this library

- Pure SwiftUI — no UIKit/AppKit bridging, no `NSItemProvider`.
- Uses `DragGesture` (not `.draggable` / `.onDrag`), so cursor-following / live rearrange behavior matches Safari rather than the system drag-preview model from #0011.
- Gesture lives on a stable `ReorderableHStack` parent; child views opt into being grab targets via `.dragHandle()`. This is exactly the architecture in the "current plan to fix" section of `0021.md`.
- `onMove(from:to:)` callback fires once per move — maps directly to the existing `TabsModel.reorderWithoutPersisting(from:to:)` + `persistTabs()` pair. No mid-drag debouncing required.
- Active maintenance, MIT licensed, builds for macOS per Swift Package Index.
- Repo: https://github.com/visfitness/reorderable

## Integration plan

### 1. Add the package

In Xcode: File → Add Package Dependencies → `https://github.com/visfitness/reorderable` → up-to-next-major from `1.3.2`.

### 2. Replace the entire reorder logic in `Issues/Views/TabBarView.swift`

Delete:
- The `displayItems` / `DisplayItem` placeholder array.
- `originalSlot`, `phantomSlot`, `originalSlotAnchor`, `dragXOffset`, `draggedWidth`, `draggingID` state.
- The `cell(for:)` switch that swaps `TabChipView` for `Color.clear`.
- The floating overlay that renders the dragged chip separately.
- The `computePhantomSlot(cursorBarX:)` helper and any cumulative-anchor math.
- Per-chip `DragGesture` and the `dragGesture(for:)` builder.
- `withTransaction(Transaction(animation: nil))` wrappers around array mutations.
- The `onGeometryChange` width measurement plumbing **if** v1 uses fixed-width chips (preferred); keep it only if you need variable widths.

Replace with roughly:

```swift
import Reorderable
import SwiftUI

struct TabBarView: View {
    @Environment(TabsModel.self) private var tabs

    var body: some View {
        HStack(spacing: 0) {
            ReorderableHStack(
                tabs.tabs,
                onMove: { from, to in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        // ReorderableHStack uses move(fromOffsets:toOffset:) semantics:
                        // when moving forward, the destination index needs +1.
                        let destination = (to > from) ? to + 1 : to
                        tabs.reorderWithoutPersisting(from: from, to: destination)
                    }
                    tabs.persistTabs()
                }
            ) { chip in
                TabChipView(chip: chip, isActive: tabs.activeTabID == chip.id)
                    .onTapGesture { tabs.setActive(id: chip.id) }
            }

            AddTabButton()  // unchanged from today
        }
    }
}
```

### 3. Add a drag handle inside `TabChipView`

`ReorderableHStack` requires children to declare which sub-region initiates the drag, via `.dragHandle()`. This is the same modifier that fixes the "accidentally closing a tab" symptom — drags only start from the handle area, so the close (X) button stays inert during a drag.

Two options:
- **Whole-chip drag.** Apply `.dragHandle()` to a background shape (e.g. the chip's `Capsule` or `RoundedRectangle`) that sits behind the label and close button. The label/icon/close button render on top with their own hit-testing intact.
- **Drag-from-label-only.** Apply `.dragHandle()` to just the title/icon HStack, leaving the close button outside the handle. More conservative; matches Safari (you can't initiate a tab drag by clicking the X).

Recommend option 2 for v1.

```swift
struct TabChipView: View {
    let chip: IssueStore
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: chip.icon)
                Text(chip.title).lineLimit(1)
            }
            .dragHandle()                       // <— grab area

            CloseTabButton(chip: chip)          // outside the handle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(/* active/inactive styling */)
        .fixedSize(horizontal: true, vertical: false)
    }
}
```

### 4. Animate the drag-state visuals via the `isDragged` parameter

`ReorderableHStack`'s content closure can take a second argument exposing whether the item is currently being dragged. Use it for the lift/scale/shadow effect that `0021.md` calls out as the desired behavior:

```swift
ReorderableHStack(tabs.tabs, onMove: { /* ... */ }) { chip, isDragged in
    TabChipView(chip: chip, isActive: tabs.activeTabID == chip.id)
        .onTapGesture { tabs.setActive(id: chip.id) }
        .scaleEffect(isDragged ? 1.04 : 1)
        .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: 14, y: 8)
        .zIndex(isDragged ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDragged)
}
```

### 5. Remove the `.draggable` / `.dropDestination` wiring from #0011

If any of it is still present (the original ticket says it should already be removed but verify), strip it now. Mixing the two patterns will fight.

## Caveats and verification

1. **macOS-specific testing.** The library's README is iOS-flavored (uses `UIColor`, mentions haptic feedback on move). Haptics are no-ops on macOS — fine. But the gesture timing constants were tuned for touch input; verify the drag feels right with a trackpad/mouse on macOS 15.6+ and adjust `minimumDistance` or animation springs if the lift threshold feels off.

2. **Swap semantic.** Verify the exact moment a neighbor moves out of the way matches the spec in `0021.md` (cursor enters another tab's slot, Safari semantic). If the library uses a different threshold (e.g. dragged-center past neighbor-center), there are two paths: (a) accept the slightly different feel — it'll still be far better than current state; or (b) fork the package and adjust the threshold logic. Do **not** wrap the library in additional gesture handling to "correct" it — that reintroduces the gesture-churn class of bugs.

3. **Variable widths.** If `TabChipView` widths vary noticeably (long repo names), the library handles this natively. If v1 uses fixed widths per the original plan, no extra work needed.

4. **Auto-scroll on overflow.** Out of scope per `0021.md`. If the bar ever overflows horizontally, wrap in a `ScrollView` and apply `.autoScrollOnEdges()` — that's the library's opt-in.

5. **`onMove` index convention.** The library follows SwiftUI's `Array.move(fromOffsets:toOffset:)` convention where moving forward requires `to + 1`. The `(to > from) ? to + 1 : to` correction in the snippet above accounts for this. Add a unit test for the reorder mapping to lock this in.

## Files to modify

- `Issues/Views/TabBarView.swift` — major simplification (target: under 80 lines, down from ~425).
- `Issues/Views/TabChipView.swift` — add `.dragHandle()` to the appropriate subview; otherwise unchanged.
- `Issues/State/TabsModel.swift` — **no changes**. `reorderWithoutPersisting(from:to:)` and `persistTabs()` stay as-is.
- `Package.swift` (or Xcode project's package list) — add `visfitness/reorderable` dependency.

## Test plan

After the swap, verify each of the symptoms documented in `0021.md` is resolved:

| Symptom from ticket | Verification step |
|---|---|
| Choppy drag | Drag a tab slowly across multiple slot midpoints. Movement should track cursor 1:1 with no flashing. |
| `.onEnded` not firing → state stuck | Drag and release in various positions (mid-bar, leading edge, past trailing edge). On every release, no overlay/placeholder remnants. |
| Accidentally closing a tab | Drag a tab over a neighbor that has a hover-revealed close button. Release. Verify the neighbor doesn't close. |
| Tap-to-activate broken | Single-click each tab without dragging. Verify activation is immediate (no perceptible delay). |
| Hit-testing offset from rendering | Click each tab in its visible position. Verify the clicked tab activates, not a different one. |

Add unit tests for the `(to > from) ? to + 1 : to` index mapping passed to `TabsModel.reorderWithoutPersisting`. Two cases minimum: forward move (e.g. 0 → 2) and backward move (e.g. 3 → 1).

## Fallback

If the library's drag behavior turns out to differ meaningfully from Safari and adjustment isn't viable, the team's own "current plan to fix" in `0021.md` (gesture on stable parent + always-render `TabChipView` with collapsed-width modifiers) is the right next thing to build. But try the library first — it's two hours of integration vs. another N commits of debugging.

## Alternative: `bonsplit` (only if scope expands)

If the product roadmap includes split panes, [`bonsplit`](https://bonsplit.alasdairmonk.com/) is a native macOS SwiftUI tab bar + split pane library with drag-reorder built in. It's a heavier adoption — Bonsplit owns tab lifecycle through its own `BonsplitController` and `BonsplitDelegate`, which would mean restructuring `TabsModel` and the per-tab `IssueStore` folder-watching wiring around its callbacks. Not recommended for this ticket; flagged here only for the roadmap.
