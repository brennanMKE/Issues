import Foundation

/// Reasons the parser may reject an otherwise well-named `NNNN.md` file.
/// Surfaced through `parseDetailed(...)` so the lint pane (#0019) can explain
/// why a file was skipped instead of silently ignoring it.
public enum MarkdownIssueParseError: Error, Equatable, Hashable, Sendable {
    /// File name doesn't match `^\d{4}\.md$` — the filename gate. Strictly
    /// speaking the linter never sees this case (it filters first), but the
    /// error is exposed for symmetry with the existing `parse(...)` contract.
    case filenameMismatch
    /// No `# NNNN \u{2014} Title` line. Most often a hyphen was used instead
    /// of an em-dash (U+2014), or the heading is missing entirely.
    case missingTitle
    /// No `| **Status** | … |` row in the metadata table.
    case missingStatus
}
