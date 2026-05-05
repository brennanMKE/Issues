import SwiftUI

struct RecentView: View {
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
        let issues = store.filteredIssues
            .sorted { $0.modifiedAt > $1.modifiedAt }

        if issues.isEmpty {
            RecentEmptyStateView()
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(issues) { issue in
                        RecentRowView(
                            issue: issue,
                            isSelected: store.selectedIssueID == issue.id,
                            onTap: { store.toggleSelection(issue.id) },
                            onOpenMarkdown: onOpenMarkdown
                        )
                        Rectangle()
                            .fill(Color.appBorder.opacity(0.4))
                            .frame(height: 1)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}
