import Foundation

/// Pre-processing pass that turns `#NNNN` mentions in issue markdown bodies
/// into clickable links via a custom `issue://` URL scheme (#0054).
///
/// The Mac app intercepts `issue://NNNN` URLs through a custom
/// `OpenURLAction` installed on `DetailPanelDescriptionView` and routes them
/// to `IssueStore.selectedIssueID`. Pre-processing keeps the regex out of the
/// rendering layer so Textual just sees normal Markdown links.
///
/// Recognition rules (mirror the issue's "Edge cases" section):
/// - exactly four digits — `#0042` matches, `#42` and `#12345` do not
/// - a non-word, non-`/` character must precede the `#` (or it must start the
///   line) so `code#0042` and `path/0042` don't match
/// - the four digits must not be followed by another digit (so `#00420`
///   doesn't sneak through)
/// - matches inside fenced code blocks (```` ``` ````) and inline code spans
///   (`` ` ``) are skipped — same exclusion `LintRunner.stripCodeSpans` uses
///   for image refs.
public enum IssueCrossRef {

    /// Custom URL scheme used to round-trip cross-references through Textual's
    /// `OpenURLAction`. The host carries the four-digit issue id.
    public static let urlScheme = "issue"

    /// Regex for the cross-reference itself. Negative lookbehind on word chars
    /// and `/` keeps URL fragments and word-internal hashes inert; negative
    /// lookahead on a digit stops `#00420` from matching `#0042`.
    private static let pattern = #"(?<![\w/])#(\d{4})(?!\d)"#

    /// Returns `markdown` with every eligible `#NNNN` mention rewritten as a
    /// Markdown link `[#NNNN](issue://NNNN)`. Fenced code blocks and inline
    /// code spans are passed through verbatim.
    public static func rewrite(_ markdown: String) -> String {
        let segments = splitOutCodeSpans(markdown)
        var result = ""
        result.reserveCapacity(markdown.count)
        for segment in segments {
            switch segment {
            case .code(let text):
                result.append(text)
            case .prose(let text):
                result.append(replaceReferences(in: text))
            }
        }
        return result
    }

    /// Parses an `issue://NNNN` URL produced by `rewrite(_:)`. Returns the
    /// four-digit id if the URL matches the scheme and host shape, otherwise
    /// nil — callers fall through to the system handler so external links
    /// (`https://…`, `mailto:…`, etc.) keep working.
    public static func issueID(from url: URL) -> String? {
        guard url.scheme == urlScheme else { return nil }
        // SwiftUI/Foundation route the digits into either the host or the
        // path depending on how the URL is constructed; accept either so the
        // pre-processor doesn't have to care.
        let candidate = url.host ?? url.lastPathComponent
        guard candidate.count == 4, candidate.allSatisfy(\.isNumber) else {
            return nil
        }
        return candidate
    }

    // MARK: - Internals

    private enum Segment {
        case prose(String)
        case code(String)
    }

    /// Walks `text` once and returns it as an alternating list of prose vs.
    /// code segments. Code includes the surrounding backticks so the segments
    /// concatenate back to the original verbatim. Two state machines run in
    /// sequence: first a fenced-block pass (``` … ```), then an inline pass
    /// (` … `) over each prose segment.
    private static func splitOutCodeSpans(_ text: String) -> [Segment] {
        let fencePass = splitOnDelimiter(text, delimiter: "```", crossLines: true)
        var out: [Segment] = []
        for segment in fencePass {
            switch segment {
            case .code:
                out.append(segment)
            case .prose(let prose):
                out.append(contentsOf: splitOnDelimiter(prose, delimiter: "`", crossLines: false))
            }
        }
        return out
    }

    /// Splits `text` into alternating prose/code segments around the given
    /// delimiter. `crossLines: true` lets a span span newlines (fenced
    /// blocks); `false` constrains a span to a single line so an unterminated
    /// stray backtick can't swallow the rest of the file. Mirrors the
    /// constraints `LintRunner.stripCodeSpans` already enforces.
    private static func splitOnDelimiter(
        _ text: String,
        delimiter: String,
        crossLines: Bool
    ) -> [Segment] {
        var segments: [Segment] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let openRange = text.range(of: delimiter, range: cursor..<text.endIndex) else {
                segments.append(.prose(String(text[cursor..<text.endIndex])))
                break
            }
            // Prose up to (but not including) the opening delimiter.
            if openRange.lowerBound > cursor {
                segments.append(.prose(String(text[cursor..<openRange.lowerBound])))
            }
            // Look for the closing delimiter. For inline spans, restrict the
            // search to the same line so an unterminated backtick doesn't eat
            // the rest of the document.
            let searchUpper: String.Index = {
                if crossLines { return text.endIndex }
                if let nl = text.range(of: "\n", range: openRange.upperBound..<text.endIndex) {
                    return nl.lowerBound
                }
                return text.endIndex
            }()
            guard let closeRange = text.range(
                of: delimiter,
                range: openRange.upperBound..<searchUpper
            ) else {
                // Unterminated delimiter — treat the rest as prose so a stray
                // backtick doesn't silently drop the tail.
                segments.append(.prose(String(text[openRange.lowerBound..<text.endIndex])))
                break
            }
            segments.append(.code(String(text[openRange.lowerBound..<closeRange.upperBound])))
            cursor = closeRange.upperBound
        }
        return segments
    }

    private static func replaceReferences(in text: String) -> String {
        // `replacingOccurrences(of:with:options:.regularExpression)` doesn't
        // support backreferences uniformly across platforms, so fall through
        // to NSRegularExpression for the substitution.
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            // Pattern is a compile-time literal; if this throws something has
            // gone very wrong upstream — fall through to the unmodified text
            // rather than crashing on user content.
            return text
        }
        let matches = regex.matches(in: text, range: range)
        if matches.isEmpty { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var cursor = 0
        for match in matches where match.numberOfRanges >= 2 {
            let full = match.range(at: 0)
            let id = match.range(at: 1)
            if full.location > cursor {
                result.append(ns.substring(
                    with: NSRange(location: cursor, length: full.location - cursor)
                ))
            }
            let idString = ns.substring(with: id)
            result.append("[#\(idString)](\(urlScheme)://\(idString))")
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            result.append(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return result
    }
}
