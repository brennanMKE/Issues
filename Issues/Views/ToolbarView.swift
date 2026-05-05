import SwiftUI
import AppKit

/// Toolbar row holding the status filter pills and the module/platform
/// pickers. The search field moved to `HeaderView` and the view-mode
/// segmented capsule moved to `StatsBarView` in #0022 — both lifts free up
/// horizontal space so the status pill labels render on a single line at
/// typical window widths.
struct ToolbarView: View {
    @Bindable var store: IssueStore

    var body: some View {
        HStack(spacing: 12) {
            statusPills

            Picker("Module", selection: $store.moduleFilter) {
                Text("All Modules").tag(String?.none)
                ForEach(store.uniqueModules, id: \.self) { module in
                    Text(module).tag(String?.some(module))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Picker("Platform", selection: $store.platformFilter) {
                Text("All Platforms").tag(String?.none)
                ForEach(store.uniquePlatforms, id: \.self) { platform in
                    Text(platform).tag(String?.some(platform))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Spacer()
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

    private var statusPills: some View {
        HStack(spacing: 6) {
            ForEach(IssueStatus.displayOrder, id: \.self) { status in
                statusPill(for: status)
            }
        }
    }

    private func statusPill(for status: IssueStatus) -> some View {
        let isActive = store.statusFilters.contains(status)
        return Button {
            handleStatusPillClick(status: status, isActive: isActive)
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
        .help("Click to filter by \(status.displayName). Option-click to add/remove from the current selection.")
    }

    /// Plain click: collapse selection to just this status, or clear if it
    /// was the only one already selected.
    /// Option-click: toggle this status's membership in the active set
    /// (allowing multi-select across statuses).
    private func handleStatusPillClick(status: IssueStatus, isActive: Bool) {
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if optionHeld {
            if isActive {
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
