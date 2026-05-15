import SwiftUI
import IssuesCore

struct RecentEmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("No issues match the current filters.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        RecentEmptyStateView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        RecentEmptyStateView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    RecentEmptyStateView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RecentEmptyStateView()
        .preferredColorScheme(.dark)
}
#endif
