import SwiftUI
import IssuesCore

/// Sheet body for `IssueMarkdownSheet`. Mirrors the right-side detail panel
/// below its header — metadata grid, divider, then description (#0048).
/// The sheet's own header (`IssueMarkdownSheetHeaderView`) stands in for the
/// detail panel's header, so we don't repeat id/title here.
struct IssueMarkdownSheetContentView: View {
    let issue: Issue
    /// Forwarded to `DetailPanelDescriptionView` so `#NNNN` mentions inside
    /// the body are clickable (#0054). When the user taps a reference while
    /// the sheet is open, the host swaps `store.selectedIssueID` and the
    /// sheet body re-renders in place.
    var onOpenIssue: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                DetailPanelMetadataView(issue: issue)
                Divider().background(Color.appBorder)
                DetailPanelDescriptionView(issue: issue, onOpenIssue: onOpenIssue)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        IssueMarkdownSheetContentView(issue: PreviewSamples.issue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        IssueMarkdownSheetContentView(issue: PreviewSamples.issue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    IssueMarkdownSheetContentView(issue: PreviewSamples.issue)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    IssueMarkdownSheetContentView(issue: PreviewSamples.issue)
        .preferredColorScheme(.dark)
}
#endif
