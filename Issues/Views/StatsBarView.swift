import SwiftUI

/// Single horizontal row showing colored count chips on the leading edge and
/// the view-mode segmented capsule on the trailing edge. The view-mode
/// capsule moved here from `ToolbarView` in #0022 so the toolbar row has
/// breathing room for the status pills and module/platform pickers.
struct StatsBarView: View {
    @Bindable var store: IssueStore
    let total: Int
    let counts: [IssueStatus: Int]

    var body: some View {
        HStack(spacing: 18) {
            statRow(color: .appAccent, label: "All", count: total)
            ForEach(IssueStatus.displayOrder, id: \.self) { status in
                let count = counts[status] ?? 0
                if count > 0 {
                    statRow(color: status.foreground, label: status.displayName, count: count)
                }
            }
            Spacer()
            viewModeSwitcher
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

    private func statRow(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appText)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
        }
    }

    private var viewModeSwitcher: some View {
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
                        .foregroundStyle(active ? Color.white : Color.appMuted)
                        .background(active ? Color.appAccentDim : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appBackgroundCard)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.appBorder, lineWidth: 1)
        )
    }
}
