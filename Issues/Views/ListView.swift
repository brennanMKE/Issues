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

    var body: some View {
        Table(sortedIssues, selection: selectionBinding, sortOrder: $sortOrder) {
            TableColumn("#", value: \.id) { issue in
                Text("#\(issue.id)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.appMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenMarkdown(issue) }
                    .contextMenu {
                        Button("Preview Markdown") { onOpenMarkdown(issue) }
                    }
            }
            .width(60)

            TableColumn("Status", value: \.status.rawValue) { issue in
                StatusBadgeView(status: issue.status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenMarkdown(issue) }
                    .contextMenu {
                        Button("Preview Markdown") { onOpenMarkdown(issue) }
                    }
            }
            .width(110)

            TableColumn("Title", value: \.title) { issue in
                Text(issue.title)
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenMarkdown(issue) }
                    .contextMenu {
                        Button("Preview Markdown") { onOpenMarkdown(issue) }
                    }
            }

            TableColumn("Module", value: \.module) { issue in
                Text(issue.module)
                    .foregroundStyle(Color.appMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenMarkdown(issue) }
                    .contextMenu {
                        Button("Preview Markdown") { onOpenMarkdown(issue) }
                    }
            }

            TableColumn("Platform", value: \.platform) { issue in
                Text(issue.platform)
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenMarkdown(issue) }
                    .contextMenu {
                        Button("Preview Markdown") { onOpenMarkdown(issue) }
                    }
            }
            .width(80)

            TableColumn("Filed", value: \.firstSeenRaw) { issue in
                Text(displayDate(issue.firstSeen, raw: issue.firstSeenRaw))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpenMarkdown(issue) }
                    .contextMenu {
                        Button("Preview Markdown") { onOpenMarkdown(issue) }
                    }
            }
            .width(100)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    private var sortedIssues: [Issue] {
        store.filteredIssues.sorted(using: sortOrder)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { store.selectedIssueID },
            set: { store.selectedIssueID = $0 }
        )
    }

    private func displayDate(_ date: Date?, raw: String) -> String {
        if let date { return Self.dateFormatter.string(from: date) }
        return raw
    }
}
