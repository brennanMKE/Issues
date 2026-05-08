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
    /// Whether the sibling `<id>/` folder exists *and* contains at least one
    /// regular file. Computed once during reload (#0071) by stat'ing the
    /// folder so the attachment filter doesn't re-stat on every view update.
    /// An empty `<id>/` folder counts as "no attachments".
    let hasAttachments: Bool

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
