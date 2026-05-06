import SwiftUI

struct TimelineView: View {
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    private static let labelGutter: CGFloat = 180
    private static let minTrackWidth: CGFloat = 600

    var body: some View {
        let issues = store.filteredIssues
        let geometry = TimelineGeometry.compute(issues: issues)
        let groups = store.groupedByPrimaryModule(issues)

        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                TimelineActivitySparkline(issues: issues)
                    .padding(.bottom, 8)
                TimelineTickHeaderView(geometry: geometry, labelGutter: Self.labelGutter)
                ForEach(groups, id: \.module) { group in
                    TimelineModuleRowView(
                        module: group.module,
                        issues: group.issues,
                        geometry: geometry,
                        labelGutter: Self.labelGutter,
                        store: store,
                        onOpenMarkdown: onOpenMarkdown
                    )
                }
            }
            .frame(minWidth: Self.labelGutter + Self.minTrackWidth, alignment: .leading)
            .padding(16)
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        TimelineView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        TimelineView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TimelineView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TimelineView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
        .preferredColorScheme(.dark)
}
#endif
