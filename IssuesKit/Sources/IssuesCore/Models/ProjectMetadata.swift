import Foundation

/// Lenient decoder for `project.json` at the root of an issues folder. Schema
/// authority is the IssuesSkill (see `RemoteAccess.md` §Project metadata).
/// Unknown fields are ignored; missing fields decode as nil so the consumer
/// falls back to today's behavior. The protocol exposes this on `IssueSource`
/// so a future remote source can serve the host's `project.json` without the
/// viewer needing on-disk access.
///
/// #0077 introduces the type. Actual reading of `project.json` is wired up
/// in #0075.
public struct ProjectMetadata: Decodable, Equatable, Sendable {
    public let name: String?
    public let url: URL?

    public init(name: String?, url: URL?) {
        self.name = name
        self.url = url
    }
}
