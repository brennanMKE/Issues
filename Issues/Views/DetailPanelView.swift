import SwiftUI

struct DetailPanelView: View {
    let issue: Issue
    let onClose: () -> Void
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                DetailPanelHeaderView(issue: issue, onClose: onClose)
                DetailPanelMetadataView(issue: issue)
                Divider().background(Color.appBorder)
                DetailPanelDescriptionView(issue: issue)
                DetailPanelFileLinkView(issue: issue, onOpenMarkdown: onOpenMarkdown)
            }
            .padding(16)
        }
        .background(Color.appBackgroundCard)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(width: 1)
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        DetailPanelView(issue: PreviewSamples.issue, onClose: {}, onOpenMarkdown: { _ in })
            .frame(width: 360, height: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        DetailPanelView(issue: PreviewSamples.issue, onClose: {}, onOpenMarkdown: { _ in })
            .frame(width: 360, height: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    DetailPanelView(issue: PreviewSamples.issue, onClose: {}, onOpenMarkdown: { _ in })
        .frame(width: 360, height: 400)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DetailPanelView(issue: PreviewSamples.issue, onClose: {}, onOpenMarkdown: { _ in })
        .frame(width: 360, height: 400)
        .preferredColorScheme(.dark)
}
#endif
