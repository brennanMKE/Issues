import SwiftUI

struct StatsBarLintBannerView: View {
    let count: Int
    let onShowLint: () -> Void

    var body: some View {
        Button(action: onShowLint) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.statusOpen)
                Text("\(count) " + (count == 1 ? "lint finding" : "lint findings"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.appBackgroundCard)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.statusOpen.opacity(0.5), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show lint findings")
        .accessibilityLabel("\(count) lint findings")
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatsBarLintBannerView(count: 3, onShowLint: {})
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatsBarLintBannerView(count: 3, onShowLint: {})
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatsBarLintBannerView(count: 3, onShowLint: {})
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatsBarLintBannerView(count: 3, onShowLint: {})
        .padding()
        .preferredColorScheme(.dark)
}
#endif
