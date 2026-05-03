import SwiftUI

struct ToolbarView: View {
    @Bindable var store: IssueStore

    var body: some View {
        HStack(spacing: 12) {
            statusPills

            Picker("Module", selection: moduleBinding) {
                Text("All Modules").tag(String?.none)
                ForEach(store.uniqueModules, id: \.self) { module in
                    Text(module).tag(String?.some(module))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Picker("Platform", selection: platformBinding) {
                Text("All Platforms").tag(String?.none)
                ForEach(store.uniquePlatforms, id: \.self) { platform in
                    Text(platform).tag(String?.some(platform))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

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

    private var statusPills: some View {
        HStack(spacing: 6) {
            ForEach(IssueStatus.displayOrder, id: \.self) { status in
                statusPill(for: status)
            }
        }
    }

    private func statusPill(for status: IssueStatus) -> some View {
        let isActive = store.statusFilter == status
        return Button {
            if isActive {
                store.statusFilter = nil
            } else {
                store.statusFilter = status
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(status.foreground)
                    .frame(width: 6, height: 6)
                Text(status.displayName)
                    .font(.system(size: 11, weight: .medium))
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

    private var moduleBinding: Binding<String?> {
        Binding(
            get: { store.moduleFilter },
            set: { store.moduleFilter = $0 }
        )
    }

    private var platformBinding: Binding<String?> {
        Binding(
            get: { store.platformFilter },
            set: { store.platformFilter = $0 }
        )
    }
}
