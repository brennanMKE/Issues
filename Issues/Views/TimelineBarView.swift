import SwiftUI

struct TimelineBarView: View {
    let issue: Issue
    let geometry: TimelineGeometry
    let trackWidth: CGFloat
    let yIndex: Int
    @Bindable var store: IssueStore
    let onOpenMarkdown: (Issue) -> Void

    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 4
    private static let minBarWidth: CGFloat = 60

    var body: some View {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let start = issue.firstSeen ?? geometry.minDate
        let end = issue.closed
            ?? calendar.date(byAdding: .day, value: 1, to: today)
            ?? today

        let startX = trackWidth * geometry.fraction(for: start)
        let endX = trackWidth * geometry.fraction(for: end)
        let width = max(endX - startX, Self.minBarWidth)
        let isSelected = store.selectedIssueID == issue.id
        let y = CGFloat(yIndex) * (Self.rowHeight + Self.rowSpacing)

        return HStack(spacing: 4) {
            Text("#\(issue.id)")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(issue.status.foreground)
                .padding(.horizontal, 6)
        }
        .frame(width: width, height: Self.rowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(issue.status.background22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.appAccent : issue.status.foreground,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .scaleEffect(y: isSelected ? 1.15 : 1.0, anchor: .center)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) { onOpenMarkdown(issue) }
        .onTapGesture { store.toggleSelection(issue.id) }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Preview Markdown") { onOpenMarkdown(issue) }
        .help("\(issue.title)")
        .offset(x: startX, y: y)
    }
}
