import SwiftUI

/// Sheet body for `IssueMarkdownSheet`. Reuses `DetailPanelDescriptionView`
/// so the sheet and the right-side detail panel render identically (#0048).
/// `DetailPanelDescriptionView` already crops above the H1 + metadata table
/// (the sheet's own header carries id + title), falls back gracefully on read
/// failure, and tags the subtree with `.id(issue.id)` from #0041 so Textual's
/// internal cache is invalidated on selection change.
struct IssueMarkdownSheetContentView: View {
    let issue: Issue

    var body: some View {
        ScrollView(.vertical) {
            DetailPanelDescriptionView(issue: issue)
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
