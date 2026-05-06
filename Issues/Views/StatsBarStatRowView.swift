import SwiftUI

struct StatsBarStatRowView: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appText)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        StatsBarStatRowView(color: .statusOpen, label: "Open", count: 5)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        StatsBarStatRowView(color: .statusOpen, label: "Open", count: 5)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    StatsBarStatRowView(color: .statusOpen, label: "Open", count: 5)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatsBarStatRowView(color: .statusOpen, label: "Open", count: 5)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
