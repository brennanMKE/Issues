import SwiftUI

struct MainView: View {
    @Bindable var store: IssueStore
    let onSwitchFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(folderURL: store.folderURL, onSwitchFolder: onSwitchFolder)
            StatsBarView(total: store.issues.count, counts: store.statusCounts)
            ToolbarView(store: store)

            HStack(spacing: 0) {
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.selectedIssue != nil {
                    DetailPanelView(
                        issue: store.selectedIssue ?? placeholderIssue,
                        onClose: { store.deselect() }
                    )
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.selectedIssueID)

            if let error = store.loadError {
                errorBanner(error)
            }
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.deselect() }
            switch store.viewMode {
            case .swimlane:
                SwimlaneView(store: store)
            case .timeline:
                TimelineView(store: store)
            case .list:
                ListView(store: store)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusOpen)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.appText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.appBackgroundCard)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appBorder).frame(height: 1)
        }
    }

    /// Fallback used only if the selected issue disappears between change
    /// observation and panel render — should not happen in practice.
    private var placeholderIssue: Issue {
        Issue(
            id: "----",
            title: "",
            status: .open,
            module: "",
            platform: "",
            firstSeen: nil,
            firstSeenRaw: "",
            closed: nil,
            closedRaw: "",
            description: "",
            fileURL: store.folderURL
        )
    }
}
