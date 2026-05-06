import SwiftUI

struct IssueMarkdownSheet: View {
    let issue: Issue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            IssueMarkdownSheetHeaderView(issue: issue, onDismiss: { dismiss() })
            Divider().background(Color.appBorder)
            IssueMarkdownSheetContentView(issue: issue)
        }
        .frame(minWidth: 600, idealWidth: 900, maxWidth: .infinity,
               minHeight: 400, idealHeight: 800, maxHeight: .infinity)
        .background(Color.appBackground)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            // Quick Look toggle (#0045): pressing space again while the
            // preview is showing dismisses it, matching Finder.
            dismiss()
            return .handled
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        IssueMarkdownSheet(issue: PreviewSamples.issue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        IssueMarkdownSheet(issue: PreviewSamples.issue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    IssueMarkdownSheet(issue: PreviewSamples.issue)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    IssueMarkdownSheet(issue: PreviewSamples.issue)
        .preferredColorScheme(.dark)
}
#endif
