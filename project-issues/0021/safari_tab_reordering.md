# Safari-Style Tab Reordering in SwiftUI

## Goal

Implement horizontal tab reordering that matches Safari's feel:

- The grabbed tab lifts (subtle scale + shadow) and stays pinned under the cursor/finger in real time.
- Neighboring tabs slide out of the way as the dragged tab crosses slot midpoints.
- On release, everything springs cleanly into place.

## Approach

The trick is to **lay out tabs by absolute x-offset inside a `ZStack` rather than using `HStack`**. That way the dragged tab can stay pinned under the cursor while neighbors animate to new positions independently.

Algorithm:

1. On drag start, capture the tab's `originalIndex` and switch its position formula to `originalX + dragOffset` (so it stops tracking its array index).
2. On each `onChanged`, compute `Int((dragOffset / stride).rounded())`. If that lands on a different slot than where the tab currently sits in the array, mutate the array (`remove` + `insert`).
3. Other tabs keep position formula `index * stride`, with `.animation(value: index)` so they spring whenever the array reorders.
4. On release, clear the dragging state — the dragged tab's formula reverts to `index * stride`, which springs it into its new home.

## Reference Implementation

```swift
import SwiftUI

struct BrowserTab: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var icon: String
    var iconColor: Color
}

struct ReorderableTabBar: View {
    @State private var tabs: [BrowserTab] = [
        .init(title: "Y Combinator",      icon: "Y", iconColor: .orange),
        .init(title: "Google",            icon: "G", iconColor: .blue),
        .init(title: "Home / Anthropic",  icon: "A", iconColor: .black),
    ]
    @State private var selection: BrowserTab.ID?
    @State private var draggingID: BrowserTab.ID?
    @State private var originalIndex: Int?
    @State private var dragXOffset: CGFloat = 0

    private let tabWidth: CGFloat = 220
    private let spacing:  CGFloat = 4
    private var stride:   CGFloat { tabWidth + spacing }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(tabs) { tab in
                let idx        = tabs.firstIndex(of: tab) ?? 0
                let isDragging = draggingID == tab.id
                let homeX      = CGFloat(idx) * stride
                let originalX  = originalIndex.map { CGFloat($0) * stride } ?? homeX
                let xPos       = isDragging ? originalX + dragXOffset : homeX

                TabPill(tab: tab, isSelected: selection == tab.id)
                    .frame(width: tabWidth)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: 14, y: 8)
                    .offset(x: xPos)
                    .zIndex(isDragging ? 1 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: idx)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDragging)
                    .contentShape(Capsule())
                    .onTapGesture { selection = tab.id }
                    .gesture(dragGesture(for: tab))
            }
        }
        .frame(width: CGFloat(tabs.count) * stride - spacing, height: 40, alignment: .leading)
        .padding(6)
        .background(Color(white: 0.18), in: Capsule())
        .onAppear { selection = tabs.last?.id }
    }

    private func dragGesture(for tab: BrowserTab) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingID == nil {
                    draggingID = tab.id
                    originalIndex = tabs.firstIndex(of: tab)
                }
                guard let origIdx = originalIndex else { return }

                dragXOffset = value.translation.width

                let slotsCrossed = Int((dragXOffset / stride).rounded())
                let targetIndex  = max(0, min(tabs.count - 1, origIdx + slotsCrossed))
                let currentIdx   = tabs.firstIndex(of: tab) ?? origIdx

                if targetIndex != currentIdx {
                    let item = tabs.remove(at: currentIdx)
                    tabs.insert(item, at: targetIndex)
                }
            }
            .onEnded { _ in
                draggingID = nil
                originalIndex = nil
                dragXOffset = 0
            }
    }
}

private struct TabPill: View {
    let tab: BrowserTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(tab.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(tab.iconColor, in: RoundedRectangle(cornerRadius: 4))
            Text(tab.title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(isSelected ? Color(white: 0.32) : .clear))
    }
}

#Preview {
    ReorderableTabBar()
        .padding()
        .background(Color(white: 0.08))
}
```

## Notes & Caveats

### Equal-width tabs
The `idx * stride` math assumes all tabs are the same width. For variable-width tabs (e.g., active tab wider than inactive), do this:

- Measure each tab's frame via a `PreferenceKey` or `onGeometryChange` (iOS 18+).
- Replace `idx * stride` with cumulative widths.
- Replace the threshold check with per-tab midpoint comparison: swap when the dragged tab's center crosses a neighbor's midpoint.

### Why not `.draggable` / `.dropDestination`?
That API is for system drag-and-drop with `Transferable` and is excellent for cross-window or cross-app drops, but it renders the system drag preview floating from the cursor — not the in-place rearrange Safari does. Once you've gone custom-gesture, you can layer `.draggable` on top if you want tabs to be tear-off-able to a new window.

### Tap vs. drag
`DragGesture(minimumDistance: 4)` plus a separate `.onTapGesture` handles tap-to-select cleanly without needing a `simultaneousGesture` setup. If you nest this in a `ScrollView`, you may need `.highPriorityGesture` for the drag.

### Rapid multi-slot flicks
The `remove` + `insert` pattern (rather than `swapAt`) correctly handles drags that span multiple slots in a single frame. If you find rapid reordering looks chaotic with many tabs, raise `dampingFraction` on the `value: idx` animation toward 0.85.

### Auto-scroll
Not implemented here. If your tab bar can overflow horizontally, add a `ScrollViewReader` and on drag, when `dragXOffset` approaches the visible bounds, programmatically `scrollTo` the nearest off-screen tab.

## Suggested Integration Tasks

1. Drop `ReorderableTabBar` into the project and verify it builds.
2. Replace the hard-coded `tabs` state with the app's actual tab model (probably from a `TabsStore` or `@Observable` view model). Persist order changes back to that store.
3. Wire `selection` to the existing routing/active-tab system.
4. If tab widths vary, swap the fixed-width math for the `PreferenceKey`-based variant described above.
5. Add tests for the reorder logic — extract `slotsCrossed`/`targetIndex` calculation into a pure function and unit-test it independently of the gesture.
