import Foundation

/// Compact, value-typed view of an issue used to detect changes between
/// reloads. Includes id, status, and file mtime so that body edits — which
/// don't change id/status — still register as "unseen changes" via `modifiedAt`.
public struct IssueSnapshot: Hashable, Sendable {
    public let id: String
    public let status: IssueStatus
    public let modifiedAt: Date

    public init(id: String, status: IssueStatus, modifiedAt: Date) {
        self.id = id
        self.status = status
        self.modifiedAt = modifiedAt
    }
}
