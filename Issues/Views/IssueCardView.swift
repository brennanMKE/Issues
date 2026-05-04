import SwiftUI

struct IssueCardView: View {
    let issue: Issue
    let isSelected: Bool
    let onTap: () -> Void
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
        HStack(spacing: 6) {
            StatusDotView(status: issue.status, size: 7)
            Text("#\(issue.id)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.appMuted)
            Text(issue.title)
                .font(.system(size: 12))
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 120, maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.appAccent.opacity(0.08) : Color.appBackgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.appAccent : Color.appBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenMarkdown(issue) }
        .onTapGesture { onTap() }
        .help(issue.title)
    }
}
