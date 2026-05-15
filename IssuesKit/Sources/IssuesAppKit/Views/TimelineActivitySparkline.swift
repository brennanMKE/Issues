import Charts
import IssuesCore
import SwiftUI

/// A small stacked bar chart showing opened-vs-closed counts per day for
/// roughly the last 30 days. Sits above the timeline tick header so the
/// dashboard tells you "what's the project's activity rhythm?" at a glance.
///
/// See project-issues/0057.md for the design doc.
struct TimelineActivitySparkline: View {
    let issues: [Issue]
    var dayCount: Int = 30

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tooltipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        let buckets = Self.makeBuckets(issues: issues, dayCount: dayCount, today: Date())

        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Day", bucket.day, unit: .day),
                    y: .value("Opened", bucket.opened),
                    stacking: .standard
                )
                .foregroundStyle(Color.statusOpen)
                .accessibilityLabel(Text(Self.tooltipFormatter.string(from: bucket.day)))
                .accessibilityValue(Text("\(bucket.opened) opened, \(bucket.closed) closed"))

                BarMark(
                    x: .value("Day", bucket.day, unit: .day),
                    y: .value("Closed", bucket.closed),
                    stacking: .standard
                )
                .foregroundStyle(Color.statusResolved)
                // Hatch the "closed" segment when the user has asked to
                // differentiate without color so the two series stay
                // distinguishable beyond hue.
                .opacity(differentiateWithoutColor ? 0.7 : 1.0)
                .accessibilityLabel(Text(Self.tooltipFormatter.string(from: bucket.day)))
                .accessibilityValue(Text("\(bucket.opened) opened, \(bucket.closed) closed"))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.appBorder.opacity(0.4))
                        .frame(height: 1)
                }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .default, value: buckets.map(\.opened))
        .animation(reduceMotion ? nil : .default, value: buckets.map(\.closed))
        .help(Self.summaryTooltip(for: buckets))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Activity sparkline, last \(dayCount) days"))
    }

    // MARK: - Bucketing

    struct Bucket: Identifiable, Equatable {
        let id: Date
        let day: Date
        let opened: Int
        let closed: Int
    }

    /// Build `dayCount` daily buckets ending today, counting issues whose
    /// `firstSeen` falls on the day (opened) and whose `closed` falls on the
    /// day (closed). Days with no activity render as zero-height bars; the
    /// baseline still shows.
    static func makeBuckets(issues: [Issue], dayCount: Int, today: Date) -> [Bucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

        let endDay = calendar.startOfDay(for: today)
        guard let startDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endDay) else {
            return []
        }

        var openedByDay: [Date: Int] = [:]
        var closedByDay: [Date: Int] = [:]

        for issue in issues {
            if let firstSeen = issue.firstSeen {
                let day = calendar.startOfDay(for: firstSeen)
                if day >= startDay && day <= endDay {
                    openedByDay[day, default: 0] += 1
                }
            }
            if let closed = issue.closed {
                let day = calendar.startOfDay(for: closed)
                if day >= startDay && day <= endDay {
                    closedByDay[day, default: 0] += 1
                }
            }
        }

        var buckets: [Bucket] = []
        buckets.reserveCapacity(dayCount)
        var cursor = startDay
        for _ in 0..<dayCount {
            buckets.append(
                Bucket(
                    id: cursor,
                    day: cursor,
                    opened: openedByDay[cursor] ?? 0,
                    closed: closedByDay[cursor] ?? 0
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return buckets
    }

    private static func summaryTooltip(for buckets: [Bucket]) -> String {
        let totalOpened = buckets.reduce(0) { $0 + $1.opened }
        let totalClosed = buckets.reduce(0) { $0 + $1.closed }
        return "Last \(buckets.count) days: \(totalOpened) opened, \(totalClosed) closed"
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 16) {
        TimelineActivitySparkline(issues: PreviewSamples.issues)
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        TimelineActivitySparkline(issues: PreviewSamples.issues)
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .padding()
}
#endif
