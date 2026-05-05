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
        // Double-tap on a cell's visible text opens the markdown sheet.
        // `simultaneousGesture` lets it fire alongside NSTableView's row
        // selection instead of racing it; skipping `contentShape(Rectangle())`
        // keeps the gesture bounded to the rendered glyph so single-clicks on
        // surrounding cell whitespace go cleanly to the Table for selection
        // (see #0040 / #0042).
        Table(sortedIssues, selection: $store.selectedIssueID, sortOrder: $sortOrder) {
            TableColumn("#", value: \.id) { issue in
                Text("#\(issue.id)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.appMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMarkdown(issue) })
            }
            .width(60)

            TableColumn("Status", value: \.status.rawValue) { issue in
                StatusBadgeView(status: issue.status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMarkdown(issue) })
            }
            .width(110)

            TableColumn("Title", value: \.title) { issue in
                Text(issue.title)
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMarkdown(issue) })
            }

            TableColumn("Module", value: \.module) { issue in
                Text(issue.module)
                    .foregroundStyle(Color.appMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMarkdown(issue) })
            }

            TableColumn("Platform", value: \.platform) { issue in
                Text(issue.platform)
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMarkdown(issue) })
            }
            .width(80)

            TableColumn("Filed", value: \.firstSeenRaw) { issue in
                Text(displayDate(issue.firstSeen, raw: issue.firstSeenRaw))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMarkdown(issue) })
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
