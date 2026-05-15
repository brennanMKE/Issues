import SwiftUI
import IssuesCore

struct StatusDotView: View {
    let status: IssueStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.foreground)
            .frame(width: size, height: size)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatusDotView(status: .open)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatusDotView(status: .open)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatusDotView(status: .open)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatusDotView(status: .open)
        .preferredColorScheme(.dark)
}
#endif
