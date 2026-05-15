import SwiftUI
import IssuesCore
import AppKit

/// A single status filter pill in the toolbar. Plain-click collapses the
/// active status filter to just this status (or clears it if it was the
/// only one already selected); Option-click toggles this status's
/// membership in the active set, with one exception (#0068): when the
/// clicked pill is the *only* active status, Option-click inverts the
/// selection — every other status becomes active and this one is
/// dropped. That makes "show me everything but X" a single keystroke.
struct ToolbarStatusPillView: View {
    let status: IssueStatus
    @Bindable var store: IssueStore

    var body: some View {
        let isActive = store.statusFilters.contains(status)
        return Button {
            handleClick(isActive: isActive)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(status.foreground)
                    .frame(width: 6, height: 6)
                Text(status.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isActive ? status.background15 : Color.appBackgroundCard)
            )
            .overlay(
                Capsule().stroke(isActive ? status.foreground : Color.appBorder, lineWidth: 1)
            )
            .foregroundStyle(isActive ? status.foreground : Color.appText)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help("Click to filter by \(status.displayName). Option-click to add/remove from the current selection; Option-click the only active pill to invert the selection.")
    }

    /// Plain click: collapse selection to just this status, or clear if it
    /// was the only one already selected.
    /// Option-click: toggle this status's membership in the active set.
    /// Option-click special case (#0068): if this pill is the *only*
    /// currently-active status, invert the selection — every other status
    /// becomes active and this one is dropped.
    private func handleClick(isActive: Bool) {
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if optionHeld {
            if isActive && store.statusFilters.count == 1 {
                // Invert: this was the sole active filter, so flip to
                // "everything except this one".
                store.statusFilters = Set(IssueStatus.displayOrder).subtracting([status])
            } else if isActive {
                store.statusFilters.remove(status)
            } else {
                store.statusFilters.insert(status)
            }
        } else {
            if isActive && store.statusFilters.count == 1 {
                store.statusFilters.removeAll()
            } else {
                store.statusFilters = [status]
            }
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        ToolbarStatusPillView(status: .open, store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        ToolbarStatusPillView(status: .open, store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    ToolbarStatusPillView(status: .open, store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ToolbarStatusPillView(status: .open, store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
