import SwiftUI

/// Single horizontal row showing colored count chips on the leading edge,
/// the search field, and the view-mode segmented capsule on the trailing
/// edge. The view-mode capsule moved here from `ToolbarView` in #0022 so the
/// toolbar row has breathing room for the status pills and module/platform
/// pickers. The search field moved here from `HeaderView` in #0028 when the
/// redundant icon + "Issues" wordmark row was dropped — the macOS titlebar
/// already carries the app identity.
struct StatsBarView: View {
    @Bindable var store: IssueStore
    let total: Int
    let counts: [IssueStatus: Int]
    /// Number of `LintFinding`s currently surfaced by the store. When > 0 a
    /// small amber banner appears between the count chips and the view-mode
    /// switcher; tapping it triggers `onShowLint`. Hidden entirely at zero so
    /// a clean folder shows no chrome.
    let lintCount: Int
    let onShowLint: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            StatsBarStatRowView(color: .appAccent, label: "All", count: total)
            ForEach(IssueStatus.displayOrder, id: \.self) { status in
                let count = counts[status] ?? 0
                if count > 0 {
                    StatsBarStatRowView(color: status.foreground, label: status.displayName, count: count)
                }
            }
            Spacer()
            if lintCount > 0 {
                StatsBarLintBannerView(count: lintCount, onShowLint: onShowLint)
            }
            StatsBarSearchField(store: store)
            StatsBarViewModeSwitcherView(store: store)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
    }
}
