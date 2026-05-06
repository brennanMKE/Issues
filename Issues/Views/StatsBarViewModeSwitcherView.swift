import SwiftUI

struct StatsBarViewModeSwitcherView: View {
    @Bindable var store: IssueStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IssueStore.ViewMode.allCases, id: \.self) { mode in
                let active = store.viewMode == mode
                Button {
                    store.viewMode = mode
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(active ? Color.accentForeground : Color.appMuted)
                        .background(active ? Color.appAccentDim : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appBackgroundCard)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatsBarViewModeSwitcherView(store: PreviewSamples.makeStore())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
