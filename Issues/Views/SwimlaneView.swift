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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        SwimlaneView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        SwimlaneView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    SwimlaneView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SwimlaneView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
        .preferredColorScheme(.dark)
}
#endif
