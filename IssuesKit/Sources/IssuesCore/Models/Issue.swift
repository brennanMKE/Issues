import Foundation

public nonisolated struct Issue: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let status: IssueStatus
    /// The raw, untrimmed status text as written in the markdown table. Kept
    /// alongside the normalized `status` so the linter can flag values that
    /// fall outside the canonical set (which `IssueStatus.init(raw:)` silently
    /// folds to `.open`).
    public let statusRaw: String
    public let module: String
    public let platform: String
    public let firstSeen: Date?
    public let firstSeenRaw: String
    public let closed: Date?
    public let closedRaw: String
    public let description: String
    public let fileURL: URL
    public let modifiedAt: Date
    /// Whether the sibling `<id>/` folder exists *and* contains at least one
    /// regular file. Computed once during reload (#0071) by stat'ing the
    /// folder so the attachment filter doesn't re-stat on every view update.
    /// An empty `<id>/` folder counts as "no attachments".
    public let hasAttachments: Bool

    public init(
        id: String,
        title: String,
        status: IssueStatus,
        statusRaw: String,
        module: String,
        platform: String,
        firstSeen: Date?,
        firstSeenRaw: String,
        closed: Date?,
        closedRaw: String,
        description: String,
        fileURL: URL,
        modifiedAt: Date,
        hasAttachments: Bool
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.statusRaw = statusRaw
        self.module = module
        self.platform = platform
        self.firstSeen = firstSeen
        self.firstSeenRaw = firstSeenRaw
        self.closed = closed
        self.closedRaw = closedRaw
        self.description = description
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
        self.hasAttachments = hasAttachments
    }

    public var modules: [String] {
        module
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var primaryModule: String {
        modules.first ?? "Unknown"
    }
}
