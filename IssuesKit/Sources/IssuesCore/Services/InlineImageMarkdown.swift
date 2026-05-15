import Foundation

/// Splits an issue's markdown body into an ordered list of chunks so the
/// renderer can lay out prose with `StructuredText` while keeping image
/// attachments as standalone, clickable views (#0056).
///
/// Textual draws attachment views through a `Canvas` `resolveSymbol` pipeline
/// (see `AttachmentView.swift` in the package source), and `Canvas` does not
/// hit-test child views — a `.onTapGesture` attached to an `Attachment.body`
/// silently never fires. We therefore can't drive the "click to enlarge"
/// affordance from inside Textual itself; we lift images out of the markdown
/// before rendering and place them as sibling SwiftUI views in a `VStack`.
///
/// The splitter mirrors `LintRunner.extractImagePaths` and
/// `IssueCrossRef.splitOutCodeSpans`: image refs inside fenced code blocks
/// (` ``` … ``` `) and inline code spans (`` ` … ` ``) are passed through
/// verbatim so illustrative markdown syntax in prose doesn't get hoisted out.
public enum InlineImageMarkdown {

    /// One contiguous span of the body. Either prose (markdown that
    /// `StructuredText` will render) or an image reference (lifted out so the
    /// host can render a clickable thumbnail).
    ///
    /// The `linkPath` on `.image` is the optional surrounding link target —
    /// the markdown shape `[![alt](image)](linkPath)` (#0073). When set and
    /// the link's UTI conforms to `.movie`, the host renders a play-button
    /// overlay and routes clicks to Quick Look instead of the attachment
    /// sheet. Plain `![alt](image)` (no surrounding link) leaves `linkPath`
    /// nil and behaves exactly as before.
    public enum Chunk: Equatable {
        case prose(String)
        case image(alt: String, path: String, linkPath: String? = nil)
    }

    /// Walks `markdown` once and returns it as an ordered chunk list. Empty
    /// prose chunks (whitespace-only) are dropped so the surrounding `VStack`
    /// doesn't get extra gaps where an image used to sit.
    public static func split(_ markdown: String) -> [Chunk] {
        let segments = splitOutCodeSpans(markdown)
        var chunks: [Chunk] = []
        for segment in segments {
            switch segment {
            case .code(let text):
                appendProse(text, into: &chunks)
            case .prose(let text):
                splitImagesInProse(text, into: &chunks)
            }
        }
        // Trim trailing whitespace-only prose so the final layout doesn't
        // gain a blank trailing block.
        if case .prose(let last) = chunks.last,
           last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.removeLast()
        }
        return chunks
    }

    // MARK: - Image extraction within prose

    /// Matches a Markdown image ref `![alt](path)` with an optional
    /// surrounding `[…](linkPath)` wrapper for the video-poster shape
    /// (#0073). Capture groups:
    ///   1. alt text
    ///   2. image path
    ///   3. (optional) link target — the wrapping `](linkPath)`, present
    ///      only when the image is enclosed in `[ … ](linkPath)`.
    /// Constrained to a single line so a stray `!` followed by a multi-line
    /// stretch can't swallow real prose. Same single-line constraint as
    /// `LintRunner.imageRefPattern`.
    private static let imageRefPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\[?!\[([^\]\n]*)\]\(([^)\n]+)\)(?:\]\(([^)\n]+)\))?"#
        )
    }()

    private static func splitImagesInProse(_ text: String, into chunks: inout [Chunk]) {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = imageRefPattern.matches(in: text, range: range)
        if matches.isEmpty {
            appendProse(text, into: &chunks)
            return
        }
        var cursor = 0
        for match in matches where match.numberOfRanges >= 3 {
            let full = match.range(at: 0)
            // The optional `[` only "counts" as part of the wrapper when the
            // closing `](linkPath)` was actually captured. If we matched the
            // bracket but not the wrapper, fall back to the inner image
            // range so a stray `[` before the image stays in prose.
            let hasWrapper = match.numberOfRanges >= 4
                && match.range(at: 3).location != NSNotFound
            let leadingBracket = ns.substring(
                with: NSRange(location: full.location, length: 1)
            ) == "["
            let effectiveStart: Int = (hasWrapper && leadingBracket)
                ? full.location
                : (leadingBracket ? full.location + 1 : full.location)
            if effectiveStart > cursor {
                appendProse(
                    ns.substring(
                        with: NSRange(location: cursor, length: effectiveStart - cursor)
                    ),
                    into: &chunks
                )
            }
            // If the regex matched a leading `[` but no wrapper closed it,
            // emit the bracket as a single-character prose chunk so it isn't
            // silently dropped.
            if leadingBracket && !hasWrapper {
                appendProse("[", into: &chunks)
            }
            let alt = ns.substring(with: match.range(at: 1))
            let path = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            let linkPath: String? = {
                guard hasWrapper else { return nil }
                let raw = ns.substring(with: match.range(at: 3))
                    .trimmingCharacters(in: .whitespaces)
                return raw.isEmpty ? nil : raw
            }()
            // External references (`https://…`, `data:…`) are left in the
            // prose so Textual can still inline them — the size-cap concern
            // doesn't apply to remote images we don't already render.
            if isLikelyExternalReference(path) {
                appendProse(ns.substring(with: full), into: &chunks)
            } else if !path.isEmpty {
                chunks.append(.image(alt: alt, path: path, linkPath: linkPath))
            }
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            appendProse(
                ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)),
                into: &chunks
            )
        }
    }

    /// Appends prose to the chunk list, merging with the previous prose chunk
    /// so consecutive segments stay one `StructuredText` invocation. Drops
    /// whitespace-only fragments outright so blank bands between an image and
    /// the next prose block don't add visual noise.
    private static func appendProse(_ text: String, into chunks: inout [Chunk]) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        if case .prose(let existing) = chunks.last {
            chunks[chunks.count - 1] = .prose(existing + text)
        } else {
            chunks.append(.prose(text))
        }
    }

    private static func isLikelyExternalReference(_ path: String) -> Bool {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return true }
        if path.hasPrefix("data:") { return true }
        if path.hasPrefix("mailto:") { return true }
        return false
    }

    // MARK: - Code-span passthrough (mirrors IssueCrossRef)

    private enum Segment {
        case prose(String)
        case code(String)
    }

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
            if openRange.lowerBound > cursor {
                segments.append(.prose(String(text[cursor..<openRange.lowerBound])))
            }
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
                segments.append(.prose(String(text[openRange.lowerBound..<text.endIndex])))
                break
            }
            segments.append(.code(String(text[openRange.lowerBound..<closeRange.upperBound])))
            cursor = closeRange.upperBound
        }
        return segments
    }
}
