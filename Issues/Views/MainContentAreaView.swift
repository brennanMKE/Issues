import SwiftUI

struct MainContentAreaView: View {
    @Bindable var store: IssueStore
    @Binding var markdownSheetIssue: Issue?

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.deselect() }
                .accessibilityHidden(true)
            switch store.viewMode {
            case .swimlane:
                SwimlaneView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            case .timeline:
                TimelineView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            case .list:
                ListView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            case .recent:
                RecentView(store: store, onOpenMarkdown: { markdownSheetIssue = $0 })
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            store.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            store.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            if let issue = store.selectedIssue {
                markdownSheetIssue = issue
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            // Quick Look-style preview (#0044). Mirrors Enter so users coming
            // from Finder / Mail / Music get the affordance they expect.
            if let issue = store.selectedIssue {
                markdownSheetIssue = issue
                return .handled
            }
            return .ignored
        }
    }
}
