import SwiftUI

struct TimelineTickHeaderView: View {
    let geometry: TimelineGeometry
    let labelGutter: CGFloat

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: labelGutter, height: 22)
            GeometryReader { proxy in
                let trackWidth = proxy.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Self.weeklyTicks(geometry: geometry), id: \.self) { date in
                        let x = trackWidth * geometry.fraction(for: date)
                        VStack(alignment: .leading, spacing: 2) {
                            Rectangle()
                                .fill(Color.appBorder.opacity(0.6))
                                .frame(width: 1, height: 6)
                            Text(Self.labelFormatter.string(from: date))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.appMuted)
                        }
                        .offset(x: x)
                    }
                }
            }
            .frame(height: 22)
        }
    }

    private static func weeklyTicks(geometry: TimelineGeometry) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        var dates: [Date] = []
        var cursor = geometry.minDate
        let weekdayMonday = 2
        var components = DateComponents()
        components.weekday = weekdayMonday

        // Cap iterations as a safety net.
        for _ in 0..<200 {
            guard let next = calendar.nextDate(
                after: cursor,
                matching: components,
                matchingPolicy: .nextTime
            ) else { break }
            if next > geometry.dispMaxDate { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        TimelineTickHeaderView(
            geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
            labelGutter: 180
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        TimelineTickHeaderView(
            geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
            labelGutter: 180
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TimelineTickHeaderView(
        geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
        labelGutter: 180
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    TimelineTickHeaderView(
        geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
        labelGutter: 180
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif
