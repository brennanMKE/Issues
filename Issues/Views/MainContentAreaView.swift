import SwiftUI
import IssuesCore

struct MainContentAreaView: View {
    @Bindable var store: IssueStore
    @Binding var showingMarkdownSheet: Bool

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.deselect() }
                .accessibilityHidden(true)
            switch store.viewMode {
            case .swimlane:
                SwimlaneView(store: store, onOpenMarkdown: openMarkdown)
            case .timeline:
                TimelineView(store: store, onOpenMarkdown: openMarkdown)
            case .list:
                ListView(store: store, onOpenMarkdown: openMarkdown)
            case .recent:
                RecentView(store: store, onOpenMarkdown: openMarkdown)
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
            if store.selectedIssue != nil {
                showingMarkdownSheet = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            // Quick Look-style preview (#0044). Mirrors Enter so users coming
            // from Finder / Mail / Music get the affordance they expect.
            if store.selectedIssue != nil {
                showingMarkdownSheet = true
                return .handled
            }
            return .ignored
        }
    }

    private func openMarkdown(_ issue: Issue) {
        store.selectedIssueID = issue.id
        showingMarkdownSheet = true
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        MainContentAreaView(store: PreviewSamples.makeStore(), showingMarkdownSheet: .constant(false))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        MainContentAreaView(store: PreviewSamples.makeStore(), showingMarkdownSheet: .constant(false))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    MainContentAreaView(store: PreviewSamples.makeStore(), showingMarkdownSheet: .constant(false))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MainContentAreaView(store: PreviewSamples.makeStore(), showingMarkdownSheet: .constant(false))
        .preferredColorScheme(.dark)
}
#endif
