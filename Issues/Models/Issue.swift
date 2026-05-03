import Foundation

struct Issue: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let status: IssueStatus
    let module: String
    let platform: String
    let firstSeen: Date?
    let firstSeenRaw: String
    let closed: Date?
    let closedRaw: String
    let description: String
    let fileURL: URL

    var modules: [String] {
        module
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var primaryModule: String {
        modules.first ?? "Unknown"
    }
}
