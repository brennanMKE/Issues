import Foundation

/// Compact, value-typed view of an issue used to detect changes between
/// reloads. Includes id, status, and file mtime so that body edits — which
/// don't change id/status — still register as "unseen changes" via `modifiedAt`.
struct IssueSnapshot: Hashable, Sendable {
    let id: String
    let status: IssueStatus
    let modifiedAt: Date
}
