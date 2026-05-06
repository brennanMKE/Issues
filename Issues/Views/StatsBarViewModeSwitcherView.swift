import SwiftUI

struct StatsBarViewModeSwitcherView: View {
    @Bindable var store: IssueStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IssueStore.ViewMode.allCases, id: \.self) { mode in
                let active = store.viewMode == mode
                Button {
                    store.viewMode = mode
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(active ? Color.accentForeground : Color.appMuted)
                        .background(active ? Color.appAccentDim : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(helpText(for: mode))
            }
        }
        .background(Color.appBackgroundCard)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.appBorder, lineWidth: 1)
        )
    }

    /// Tooltip text for a view-mode segment. Renders the mode's display name
    /// plus the user's currently-bound shortcut glyph, so the tooltip stays in
    /// sync with whatever the user picked in Settings → Shortcuts (#0053).
    private func helpText(for mode: IssueStore.ViewMode) -> String {
        let action: ShortcutAction = switch mode {
        case .swimlane: .swimlanesView
        case .timeline: .timelineView
        case .list:     .listView
        case .recent:   .recentView
        }
        let glyph = AppCommandsController.shared.shortcuts.binding(for: action).displayString
        return "\(mode.displayName) (\(glyph))"
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
