import SwiftUI

struct RecentRowView: View {
    let issue: Issue
    let isSelected: Bool
    let onTap: () -> Void
    let onOpenMarkdown: (Issue) -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            StatusDotView(status: issue.status)
            Text("#\(issue.id)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.appMuted)
                .frame(minWidth: 48, alignment: .leading)
            Text(issue.title)
                .font(.system(size: 12))
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(Self.relativeFormatter.localizedString(for: issue.modifiedAt, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .help(issue.modifiedAt.formatted(date: .abbreviated, time: .standard))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.appAccent.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenMarkdown(issue) }
        .onTapGesture { onTap() }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Preview Markdown") { onOpenMarkdown(issue) }
    }
}
