import SwiftUI

struct SwimlaneModuleSectionView: View {
    let module: String
    let issues: [Issue]
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
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
