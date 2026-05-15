import SwiftUI
import IssuesCore

/// Builds an `AttributedString` from `text` with every case-insensitive
/// occurrence of `query` highlighted using an accent-tinted background.
/// Trims whitespace from the query; an empty / whitespace-only query
/// returns the plain text unchanged so callers don't need to branch
/// at the call site (#0051).
///
/// Multiple matches are highlighted, not just the first — the loop walks
/// the remaining range after each hit. The match uses `.caseInsensitive`
/// to mirror `IssueStore.filteredIssues`, which lower-cases both sides
/// before comparing.
enum SearchHighlight {
    /// Background tint applied to matched substrings. The accent color
    /// adapts to light/dark mode via `Color.appAccent` (alias for
    /// `Color.accentColor`); 0.30 keeps the swatch legible against both
    /// `Color.appText` and the various row backgrounds without overwhelming
    /// the surrounding text.
    static let backgroundOpacity: Double = 0.30

    static func attributedString(for text: String, query: String) -> AttributedString {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var attr = AttributedString(text)
        guard !trimmed.isEmpty, !text.isEmpty else { return attr }

        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: trimmed, options: .caseInsensitive, range: searchRange) {
            if let attrRange = Range(match, in: attr) {
                attr[attrRange].backgroundColor = Color.appAccent.opacity(backgroundOpacity)
            }
            // Advance past this match. Using `upperBound` (not `lowerBound + 1`)
            // avoids re-matching inside the same hit; the loop terminates when
            // `range(of:)` finds nothing in what remains.
            searchRange = match.upperBound..<text.endIndex
        }
        return attr
    }
}

extension Text {
    /// Renders `text` as a `Text`, highlighting every case-insensitive
    /// occurrence of the trimmed `query`. Empty / whitespace-only queries
    /// fall through to the plain `Text(_:)` initializer.
    init(_ text: String, highlighting query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.init(text)
            return
        }
        self.init(SearchHighlight.attributedString(for: text, query: query))
    }
}
