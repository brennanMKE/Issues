import SwiftUI

struct TimelineModuleRowView: View {
    let module: String
    let issues: [Issue]
    let geometry: TimelineGeometry
    let labelGutter: CGFloat
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        let totalHeight = max(
            CGFloat(issues.count) * (Self.rowHeight + Self.rowSpacing),
            Self.rowHeight
        )
        return HStack(alignment: .top, spacing: 0) {
            Text(module)
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Color.appMuted)
                .frame(width: labelGutter, alignment: .leading)
                .padding(.trailing, 8)

            GeometryReader { proxy in
                let trackWidth = proxy.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.appBackgroundCard.opacity(0.4))
                    TimelineTodayMarkerView(geometry: geometry, trackWidth: trackWidth)
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                        TimelineBarView(
                            issue: issue,
                            geometry: geometry,
                            trackWidth: trackWidth,
                            yIndex: index,
                            store: store,
                            onOpenMarkdown: onOpenMarkdown
                        )
                    }
                }
            }
            .frame(height: totalHeight)
        }
        .frame(height: totalHeight)
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        TimelineModuleRowView(
            module: "Views",
            issues: PreviewSamples.issues,
            geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
            labelGutter: 180,
            store: PreviewSamples.makeStore(),
            onOpenMarkdown: { _ in }
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        TimelineModuleRowView(
            module: "Views",
            issues: PreviewSamples.issues,
            geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
            labelGutter: 180,
            store: PreviewSamples.makeStore(),
            onOpenMarkdown: { _ in }
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TimelineModuleRowView(
        module: "Views",
        issues: PreviewSamples.issues,
        geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
        labelGutter: 180,
        store: PreviewSamples.makeStore(),
        onOpenMarkdown: { _ in }
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    TimelineModuleRowView(
        module: "Views",
        issues: PreviewSamples.issues,
        geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
        labelGutter: 180,
        store: PreviewSamples.makeStore(),
        onOpenMarkdown: { _ in }
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif
