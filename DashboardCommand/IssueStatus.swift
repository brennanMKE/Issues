// Duplicated from Issues/Models/IssueStatus.swift per #0133 — keep in sync; canonical has IssuesTests/MarkdownIssueParserTests.swift coverage.

import Foundation

nonisolated enum IssueStatus: String, CaseIterable, Hashable, Codable, Sendable {
    case open
    case inProgress = "in-progress"
    case resolved
    case closed
    case wontfix

    init(raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: "\\s+",
                with: "-",
                options: .regularExpression
            )
        self = IssueStatus(rawValue: normalized) ?? .open
    }

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .resolved: return "Resolved"
        case .closed: return "Closed"
        case .wontfix: return "Won't Fix"
        }
    }

    static let displayOrder: [IssueStatus] = [.open, .inProgress, .resolved, .closed, .wontfix]
}
