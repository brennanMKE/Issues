import SwiftUI

struct StatusBadgeView: View {
    let status: IssueStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(status.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(status.background15)
            )
            .overlay(
                Capsule().stroke(status.foreground.opacity(0.4), lineWidth: 1)
            )
    }
}
