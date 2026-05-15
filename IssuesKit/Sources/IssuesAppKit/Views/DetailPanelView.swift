import SwiftUI
import IssuesCore

struct DetailPanelView: View {
    let issue: Issue
    var searchQuery: String = ""
    let onClose: () -> Void
    let onOpenMarkdown: (Issue) -> Void
    /// Forwarded to `DetailPanelDescriptionView` so `#NNNN` mentions inside
    /// the body are clickable (#0054). `nil` in previews / standalone hosts.
    var onOpenIssue: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                DetailPanelHeaderView(issue: issue, searchQuery: searchQuery, onClose: onClose)
                DetailPanelMetadataView(issue: issue)
                Divider().background(Color.appBorder)
                DetailPanelDescriptionView(issue: issue, onOpenIssue: onOpenIssue)
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
