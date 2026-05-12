import Foundation

enum IssueStatus: String, CaseIterable, Hashable, Codable, Sendable {
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
        case .open: return String(localized: "Open")
        case .inProgress: return String(localized: "In Progress")
        case .resolved: return String(localized: "Resolved")
        case .closed: return String(localized: "Closed")
        case .wontfix: return String(localized: "Won't Fix")
        }
    }

    static let displayOrder: [IssueStatus] = [.open, .inProgress, .resolved, .closed, .wontfix]
}
