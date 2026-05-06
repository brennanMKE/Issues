import SwiftUI

struct ListView: View {
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void
    @State private var sortOrder: [KeyPathComparator<Issue>] = [
        KeyPathComparator(\Issue.id, order: .forward)
    ]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // No per-cell gesture recognizers: any count: 2 recognizer (even
    // simultaneousGesture) delays single-click selection enough that
    // NSTableView intermittently drops the row click. Double-click open is
    // covered by the right-click context menu and Enter keypress instead
    // (#0040 / #0042 / #0043).
    var body: some View {
        Table(sortedIssues, selection: $store.selectedIssueID, sortOrder: $sortOrder) {
            TableColumn("#", value: \.id) { issue in
                Text("#\(issue.id)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.appMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(60)

            TableColumn("Status", value: \.status.rawValue) { issue in
                StatusBadgeView(status: issue.status)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(110)

            TableColumn("Title", value: \.title) { issue in
                Text(issue.title)
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TableColumn("Module", value: \.module) { issue in
                Text(issue.module)
                    .foregroundStyle(Color.appMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TableColumn("Platform", value: \.platform) { issue in
                Text(issue.platform)
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(80)

            TableColumn("Filed", value: \.firstSeenRaw) { issue in
                Text(displayDate(issue.firstSeen, raw: issue.firstSeenRaw))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(100)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let issue = store.issues.first(where: { $0.id == id }) {
                Button("Preview Markdown") { onOpenMarkdown(issue) }
            }
        }
    }

    private var sortedIssues: [Issue] {
        store.filteredIssues.sorted(using: sortOrder)
    }

    private func displayDate(_ date: Date?, raw: String) -> String {
        if let date { return Self.dateFormatter.string(from: date) }
        return raw
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        ListView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        ListView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    ListView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ListView(store: PreviewSamples.makeStore(), onOpenMarkdown: { _ in })
        .preferredColorScheme(.dark)
}
#endif
