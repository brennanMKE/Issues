import Foundation

struct Issue: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let status: IssueStatus
    /// The raw, untrimmed status text as written in the markdown table. Kept
    /// alongside the normalized `status` so the linter can flag values that
    /// fall outside the canonical set (which `IssueStatus.init(raw:)` silently
    /// folds to `.open`).
    let statusRaw: String
    let module: String
    let platform: String
    let firstSeen: Date?
    let firstSeenRaw: String
    let closed: Date?
    let closedRaw: String
    let description: String
    let fileURL: URL
    let modifiedAt: Date

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
