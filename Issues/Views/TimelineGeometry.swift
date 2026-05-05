import Foundation

struct TimelineGeometry {
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
