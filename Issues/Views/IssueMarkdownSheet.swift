import SwiftUI

struct IssueMarkdownSheet: View {
    @Bindable var store: IssueStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let issue = store.selectedIssue {
                IssueMarkdownSheetHeaderView(issue: issue, searchQuery: store.searchQuery, onDismiss: { dismiss() })
                Divider().background(Color.appBorder)
                IssueMarkdownSheetContentView(issue: issue, onOpenIssue: openIssue)
            } else {
                // Defensive: callers should always set selection before
                // presenting, but render a clean empty surface and dismiss
                // rather than crashing if that contract is broken.
                Color.clear.onAppear { dismiss() }
            }
        }
        .frame(minWidth: 720, idealWidth: 1080, maxWidth: .infinity,
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
        .onKeyPress(.upArrow) {
            // Arrow nav while preview is open (#0049): walks the list and
            // swaps the body in place. .id(issue.id) on
            // DetailPanelDescriptionView (#0041) invalidates Textual's
            // cache as the issue changes.
            store.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            store.selectNext()
            return .handled
        }
    }

    /// Routes a `#NNNN` cross-reference click (#0054) to the underlying store.
    /// The sheet stays mounted; `IssueMarkdownSheetContentView` re-resolves
    /// `store.selectedIssue` and Textual rebuilds via `.id(issue.id)`. Misses
    /// (referenced id not in this folder) leave selection untouched so the
    /// click no-ops cleanly rather than blanking the sheet.
    private func openIssue(_ id: String) {
        guard store.issues.contains(where: { $0.id == id }) else { return }
        store.selectedIssueID = id
    }
}

#if DEBUG
private func makePreviewStore() -> IssueStore {
    let store = PreviewSamples.makeStore()
    store.selectedIssueID = PreviewSamples.issue.id
    return store
}

#Preview("Light & Dark") {
    VStack(spacing: 0) {
        IssueMarkdownSheet(store: makePreviewStore())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        IssueMarkdownSheet(store: makePreviewStore())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    IssueMarkdownSheet(store: makePreviewStore())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    IssueMarkdownSheet(store: makePreviewStore())
        .preferredColorScheme(.dark)
}
#endif
