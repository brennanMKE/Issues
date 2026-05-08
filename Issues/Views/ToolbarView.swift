import SwiftUI

/// Toolbar row holding the status filter pills and the module/platform
/// pickers. The search field moved to `HeaderView` and the view-mode
/// segmented capsule moved to `StatsBarView` in #0022 — both lifts free up
/// horizontal space so the status pill labels render on a single line at
/// typical window widths.
struct ToolbarView: View {
    @Bindable var store: IssueStore

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(IssueStatus.displayOrder, id: \.self) { status in
                    ToolbarStatusPillView(status: status, store: store)
                }
            }

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

            // Tri-state attachment filter (#0071). Styled as a menu picker
            // to match the Module / Platform dropdowns; AND-composes with
            // them in `IssueStore.filteredIssues`.
            Picker("Attachments", selection: $store.attachmentFilter) {
                Text("All Attachments").tag(IssueStore.AttachmentFilter.all)
                Text("With attachments").tag(IssueStore.AttachmentFilter.withAttachments)
                Text("Without attachments").tag(IssueStore.AttachmentFilter.withoutAttachments)
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
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        ToolbarView(store: PreviewSamples.makeStore())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        ToolbarView(store: PreviewSamples.makeStore())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    ToolbarView(store: PreviewSamples.makeStore())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ToolbarView(store: PreviewSamples.makeStore())
        .preferredColorScheme(.dark)
}
#endif
