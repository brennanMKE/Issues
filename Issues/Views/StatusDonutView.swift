import SwiftUI
import IssuesCore
import Charts

#if os(macOS)

/// Donut chart rendering one slice per `IssueStatus` (#0065). Used by
/// `ReportGenerator` (#0064) as the inline status snapshot at the top of
/// the generated `report-<date>.md`.
///
/// Light-mode forced: the chart is exported as a PNG that needs to read
/// the same in any markdown viewer regardless of the host's appearance.
struct StatusDonutView: View {

    let counts: [IssueStatus: Int]

    var body: some View {
        Chart(slices, id: \.status) { slice in
            SectorMark(
                angle: .value("Count", slice.count),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(slice.status.foreground)
            .annotation(position: .overlay) {
                Text("\(slice.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 360, height: 240)
        .padding(20)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var slices: [(status: IssueStatus, count: Int)] {
        IssueStatus.displayOrder.compactMap {
            guard let n = counts[$0], n > 0 else { return nil }
            return ($0, n)
        }
    }
}

#endif
