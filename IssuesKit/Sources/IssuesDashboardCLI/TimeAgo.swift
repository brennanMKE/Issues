// TimeAgo.swift
//
// "time since" formatting with the largest non-zero unit. Output is always
// at most 4 characters wide (e.g. "now", "30s", "5m", "2h", "3d", "5w",
// "999y") so the MODIFIED column can use a fixed 8-char frame.

import Foundation

enum TimeAgo {
    static func format(_ date: Date, relativeTo now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        let seconds = Int(interval)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(cap(minutes))m" }

        let hours = minutes / 60
        if hours < 24 { return "\(cap(hours))h" }

        let days = hours / 24
        if days < 7 { return "\(cap(days))d" }

        let weeks = days / 7
        if weeks < 52 { return "\(cap(weeks))w" }

        let years = days / 365
        return "\(cap(years))y"
    }

    private static func cap(_ value: Int) -> Int {
        return min(value, 999)
    }
}
