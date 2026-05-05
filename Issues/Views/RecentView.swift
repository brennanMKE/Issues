import SwiftUI

struct RecentView: View {
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        let issues = store.filteredIssues
            .sorted { $0.modifiedAt > $1.modifiedAt }

        if issues.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(issues) { issue in
                        row(for: issue)
                        Rectangle()
                            .fill(Color.appBorder.opacity(0.4))
                            .frame(height: 1)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func row(for issue: Issue) -> some View {
        let isSelected = store.selectedIssueID == issue.id
        return HStack(spacing: 12) {
            StatusDotView(status: issue.status)
            Text("#\(issue.id)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.appMuted)
                .frame(minWidth: 48, alignment: .leading)
            Text(issue.title)
                .font(.system(size: 12))
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(Self.relativeFormatter.localizedString(for: issue.modifiedAt, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .help(issue.modifiedAt.formatted(date: .abbreviated, time: .standard))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.appAccent.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenMarkdown(issue) }
        .onTapGesture { store.toggleSelection(issue.id) }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Preview Markdown") { onOpenMarkdown(issue) }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No issues match the current filters.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
