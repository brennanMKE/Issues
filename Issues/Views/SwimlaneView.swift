import SwiftUI

struct SwimlaneView: View {
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.module) { group in
                    moduleSection(module: group.module, issues: group.issues)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var groups: [(module: String, issues: [Issue])] {
        store.groupedByPrimaryModule(store.filteredIssues)
    }

    private func moduleSection(module: String, issues: [Issue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(module)
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Color.appMuted)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(issues) { issue in
                    IssueCardView(
                        issue: issue,
                        isSelected: store.selectedIssueID == issue.id,
                        onTap: { store.toggleSelection(issue.id) },
                        onOpenMarkdown: onOpenMarkdown
                    )
                }
            }
        }
    }
}
