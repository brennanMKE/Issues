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
enum InlineImageMarkdown {

    /// One contiguous span of the body. Either prose (markdown that
    /// `StructuredText` will render) or an image reference (lifted out so the
    /// host can render a clickable thumbnail).
    enum Chunk: Equatable {
        case prose(String)
        case image(alt: String, path: String)
    }

    /// Walks `markdown` once and returns it as an ordered chunk list. Empty
    /// prose chunks (whitespace-only) are dropped so the surrounding `VStack`
    /// doesn't get extra gaps where an image used to sit.
    static func split(_ markdown: String) -> [Chunk] {
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

    /// Matches a Markdown image ref `![alt](path)`. Same shape as
    /// `LintRunner.imageRefPattern` plus a capture for the alt text. Constrained
    /// to a single line so a stray `!` followed by a multi-line stretch can't
    /// swallow real prose.
    private static let imageRefPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(([^)\n]+)\)"#)
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
            if full.location > cursor {
                appendProse(
                    ns.substring(with: NSRange(location: cursor, length: full.location - cursor)),
                    into: &chunks
                )
            }
            let alt = ns.substring(with: match.range(at: 1))
            let path = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            // External references (`https://…`, `data:…`) are left in the
            // prose so Textual can still inline them — the size-cap concern
            // doesn't apply to remote images we don't already render.
            if isLikelyExternalReference(path) {
                appendProse(ns.substring(with: full), into: &chunks)
            } else if !path.isEmpty {
                chunks.append(.image(alt: alt, path: path))
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
