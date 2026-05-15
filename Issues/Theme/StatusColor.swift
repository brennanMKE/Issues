import SwiftUI
import IssuesCore

extension IssueStatus {
    var foreground: Color {
        switch self {
        case .open: return .statusOpen
        case .inProgress: return .statusInProgress
        case .resolved: return .statusResolved
        case .closed: return .statusClosed
        case .wontfix: return .statusWontfix
        }
    }

    var background15: Color {
        foreground.opacity(0.15)
    }

    var background22: Color {
        foreground.opacity(0.22)
    }
}
