import Foundation

/// A single lint warning surfaced by `LintRunner`. Read-only — the app never
/// auto-fixes these, only displays them so the user can decide whether to act.
public struct LintFinding: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A `NNNN.md` file that the parser couldn't turn into an `Issue`.
        case parseFailure(reason: String)
        /// A sibling `NNNN/` attachment folder with no matching `NNNN.md`.
        case orphanFolder
        /// A markdown image reference that doesn't resolve on disk.
        case missingAttachment(path: String)
        /// A Status field with a value outside the canonical set.
        case unknownStatus(raw: String)
        /// Two parsed issues sharing the same id (rare — filename collision
        /// would already prevent this on disk; this catches title-declared id
        /// drift if the filename gate is ever loosened).
        case duplicateID(otherFileURL: URL)
    }

    public let id: UUID
    /// The file (or folder, for `.orphanFolder`) the finding applies to. Used
    /// by the "Reveal in Finder" action in the lint sheet.
    public let fileURL: URL
    public let kind: Kind
    /// One-line human-readable summary, e.g.
    /// `"0007.md is missing a Status field"`.
    public let summary: String

    public init(fileURL: URL, kind: Kind, summary: String) {
        self.id = UUID()
        self.fileURL = fileURL
        self.kind = kind
        self.summary = summary
    }
}
