import SwiftUI

private struct TimelineGeometry {
    let minDate: Date
    let dispMaxDate: Date

    var span: TimeInterval {
        max(dispMaxDate.timeIntervalSince(minDate), 1)
    }

    func fraction(for date: Date) -> Double {
        let raw = date.timeIntervalSince(minDate) / span
        return min(max(raw, 0), 1)
    }

    static func compute(issues: [Issue], today: Date = Date()) -> TimelineGeometry {
        let calendar = Calendar(identifier: .gregorian)
        let firstSeenDates = issues.compactMap(\.firstSeen)
        let closedDates = issues.compactMap(\.closed)

        let earliest = firstSeenDates.min() ?? today
        let latestClosed = closedDates.max() ?? today
        let maxDate = max(latestClosed, today)

        let minDate = calendar.date(byAdding: .day, value: -1, to: earliest) ?? earliest
        let endDate = calendar.date(byAdding: .day, value: 2, to: maxDate) ?? maxDate

        let actualSpan = endDate.timeIntervalSince(minDate)
        let minSpan: TimeInterval = 14 * 86_400
        let span = max(actualSpan, minSpan)

        let dispMaxDate = minDate.addingTimeInterval(span)
        return TimelineGeometry(minDate: minDate, dispMaxDate: dispMaxDate)
    }
}

struct TimelineView: View {
    @Bindable var store: IssueStore

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let labelGutter: CGFloat = 180
    private static let minTrackWidth: CGFloat = 600
    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        let issues = store.filteredIssues
        let geometry = TimelineGeometry.compute(issues: issues)
        let groups = store.groupedByPrimaryModule(issues)

        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                tickHeader(geometry: geometry)
                ForEach(groups, id: \.module) { group in
                    moduleRow(
                        module: group.module,
                        issues: group.issues,
                        geometry: geometry
                    )
                }
            }
            .frame(minWidth: Self.labelGutter + Self.minTrackWidth, alignment: .leading)
            .padding(16)
        }
    }

    private func tickHeader(geometry: TimelineGeometry) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.labelGutter, height: 22)
            GeometryReader { proxy in
                let trackWidth = proxy.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(weeklyTicks(geometry: geometry), id: \.self) { date in
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

    private func moduleRow(
        module: String,
        issues: [Issue],
        geometry: TimelineGeometry
    ) -> some View {
        let totalHeight = max(
            CGFloat(issues.count) * (Self.rowHeight + Self.rowSpacing),
            Self.rowHeight
        )
        return HStack(alignment: .top, spacing: 0) {
            Text(module)
                .font(.system(size: 11, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Color.appMuted)
                .frame(width: Self.labelGutter, alignment: .leading)
                .padding(.trailing, 8)

            GeometryReader { proxy in
                let trackWidth = proxy.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.appBackgroundCard.opacity(0.4))
                    todayMarker(geometry: geometry, trackWidth: trackWidth)
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                        bar(
                            issue: issue,
                            geometry: geometry,
                            trackWidth: trackWidth,
                            yIndex: index
                        )
                    }
                }
            }
            .frame(height: totalHeight)
        }
        .frame(height: totalHeight)
        .padding(.vertical, 4)
    }

    private func bar(
        issue: Issue,
        geometry: TimelineGeometry,
        trackWidth: CGFloat,
        yIndex: Int
    ) -> some View {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let start = issue.firstSeen ?? geometry.minDate
        let end = issue.closed
            ?? calendar.date(byAdding: .day, value: 1, to: today)
            ?? today

        let startX = trackWidth * geometry.fraction(for: start)
        let endX = trackWidth * geometry.fraction(for: end)
        let width = max(endX - startX, 14)
        let isSelected = store.selectedIssueID == issue.id
        let y = CGFloat(yIndex) * (Self.rowHeight + Self.rowSpacing)

        return Button {
            store.toggleSelection(issue.id)
        } label: {
            HStack(spacing: 4) {
                Text("#\(issue.id)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(issue.status.foreground)
                    .padding(.horizontal, 6)
            }
            .frame(width: width, height: Self.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(issue.status.background22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.appAccent : issue.status.foreground,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(y: isSelected ? 1.15 : 1.0, anchor: .center)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("\(issue.title)")
        .offset(x: startX, y: y)
    }

    private func todayMarker(
        geometry: TimelineGeometry,
        trackWidth: CGFloat
    ) -> some View {
        let today = Date()
        let x = trackWidth * geometry.fraction(for: today)
        return Rectangle()
            .fill(Color.appAccent.opacity(0.6))
            .frame(width: 1)
            .offset(x: x)
    }

    private func weeklyTicks(geometry: TimelineGeometry) -> [Date] {
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
