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
