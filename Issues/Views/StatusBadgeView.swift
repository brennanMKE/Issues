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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatusBadgeView(status: .inProgress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatusBadgeView(status: .inProgress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatusBadgeView(status: .inProgress)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatusBadgeView(status: .inProgress)
        .preferredColorScheme(.dark)
}
#endif
