import SwiftUI
import IssuesCore

/// A 6pt-wide invisible vertical strip that lets the user drag-resize the
/// detail panel by its leading edge (#0069). The cursor flips to the
/// horizontal-resize cursor on hover so the affordance is discoverable
/// without painting a visible divider — the existing `Color.appBorder` line
/// inside `DetailPanelView` already provides the visual separator.
///
/// The handle is purely a gesture target: it converts horizontal drag
/// translation into a delta passed back via `onResize`, and the parent
/// (`MainView`) is responsible for clamping against the window width and
/// persisting the chosen value. Tracking the start width via
/// `@State` keeps each drag absolute relative to its starting point so the
/// panel doesn't accumulate float drift across many drags.
struct DetailPanelResizeHandle: View {
    /// Current panel width at the moment the drag starts. Captured so the
    /// gesture can compute a stable absolute target instead of integrating
    /// per-event deltas (which causes drift if any update is dropped).
    let currentWidth: CGFloat

    /// Called with each in-flight proposed width. The parent clamps to
    /// `[280, windowWidth / 3]` and assigns to the persisted `@AppStorage`
    /// value; SwiftUI re-lays out on the next tick.
    let onResize: (CGFloat) -> Void

    @State private var dragStartWidth: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: 6)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartWidth ?? currentWidth
                        if dragStartWidth == nil {
                            dragStartWidth = start
                        }
                        // Dragging the leading edge LEFT (negative x) widens
                        // the panel; dragging RIGHT shrinks it.
                        onResize(start - value.translation.width)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}

#if DEBUG
#Preview("Handle") {
    HStack(spacing: 0) {
        Color.appBackground
        DetailPanelResizeHandle(currentWidth: 360, onResize: { _ in })
        Color.appBackgroundCard.frame(width: 360)
    }
    .frame(width: 600, height: 200)
}
#endif
