import SwiftUI

struct StatsBarView: View {
    let total: Int
    let counts: [IssueStatus: Int]

    var body: some View {
        HStack(spacing: 18) {
            statRow(color: .appAccent, label: "All", count: total)
            ForEach(IssueStatus.displayOrder, id: \.self) { status in
                let count = counts[status] ?? 0
                if count > 0 {
                    statRow(color: status.foreground, label: status.displayName, count: count)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
    }

    private func statRow(color: Color, label: String, count: Int) -> some View {
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
