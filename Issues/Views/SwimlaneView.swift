import SwiftUI

struct SwimlaneView: View {
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(store.groupedByPrimaryModule(store.filteredIssues), id: \.module) { group in
                    SwimlaneModuleSectionView(
                        module: group.module,
                        issues: group.issues,
                        store: store,
                        onOpenMarkdown: onOpenMarkdown
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
