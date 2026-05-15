import SwiftUI
import IssuesCore
import Textual
// `.quickLookPreview($url)` (#0073) is declared in the QuickLook overlay
// module — SwiftUI re-exports it on iOS but on macOS the symbol lives behind
// `import QuickLook`. Without this import the compiler reports the modifier
// missing on `some View`.
import QuickLook

struct DetailPanelDescriptionView: View {
    let issue: Issue
    /// Optional callback invoked when the user clicks a `#NNNN` cross-
    /// reference link inside the markdown body (#0054). The argument is the
    /// four-digit id parsed out of the `issue://NNNN` URL. When `nil`, the
    /// click no-ops cleanly — previews and standalone hosts that don't have a
    /// store don't crash.
    var onOpenIssue: ((String) -> Void)? = nil

    /// File URL of an attachment the user clicked. Bound to the system Quick
    /// Look panel via `.quickLookPreview`. Setting it non-nil presents Quick
    /// Look (the same panel Finder shows on Space-bar); SwiftUI clears it back
    /// to nil when the user dismisses the panel.
    ///
    /// Images and videos both flow through this single binding (#0109);
    /// before, images used a custom `AttachmentSheet` and only videos used
    /// Quick Look (#0073). Quick Look handles images, PDFs, logs, etc.
    /// natively, so a single panel covers every attachment type.
    @State private var quickLookURL: URL?

    /// Cached body parse keyed by `(issue.id, modifiedAt)` (#0072). Reading
    /// the file from disk and rebuilding the chunk list on every body recompute
    /// caused visible jitter when the user dragged the resize handle (#0069):
    /// each drag tick changed `panelWidth` upstream in `MainView`, which re-ran
    /// this view's body, which re-read the file and re-parsed it. The cache
    /// short-circuits the disk I/O and the split, and `BodyView`'s `Equatable`
    /// conformance further short-circuits the rendered subtree on width-only
    /// changes. Refreshed via `.task(id:)` keyed on issue identity + mtime so
    /// FSEvents-driven content edits still surface.
    @State private var parsedBody: ParsedBody = .empty

    var body: some View {
        Group {
            if let body = parsedBody.body {
                EquatableView(content: BodyView(
                    issueID: parsedBody.issueID,
                    modifiedAt: parsedBody.modifiedAt,
                    bodyText: body,
                    baseURL: issue.fileURL.deletingLastPathComponent(),
                    chunks: parsedBody.chunks,
                    onOpenIssue: onOpenIssue,
                    onOpenAttachment: { quickLookURL = $0 },
                    onPlayVideo: { quickLookURL = $0 }
                ))
            } else if !issue.description.isEmpty {
                Text(issue.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No description")
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundStyle(Color.appMuted)
            }
        }
        // Textual's StructuredText caches its laid-out content internally and
        // doesn't refresh when the `markdown:` parameter changes on a same-
        // identity view. Tagging the subtree with the issue id forces SwiftUI
        // to discard and rebuild on every selection change.
        .id(issue.id)
        // Refresh the cached parse whenever the issue changes identity OR the
        // file's `modifiedAt` ticks (FSEvents-driven save in #0072 territory).
        // The body of `task` runs synchronously up to the first `await`; we
        // load synchronously here because the parse is millisecond-scale on
        // typical inputs and `IssueStore` already runs on the main actor.
        .task(id: parseCacheKey) {
            let fresh = ParsedBody.load(from: issue)
            if fresh != parsedBody {
                parsedBody = fresh
            }
        }
        // System Quick Look preview for every attachment (images, videos,
        // PDFs, logs — anything Quick Look has a generator for). Renders
        // standard pan / pinch-zoom / arrow-key navigation / "open with" /
        // share affordances for free; when the user dismisses the panel
        // SwiftUI resets the binding to nil. macOS 13+ API; this project is
        // 15+ so no availability annotation is needed. Replaces the custom
        // `AttachmentSheet` modal that previously handled images (#0109).
        .quickLookPreview($quickLookURL)
    }

    /// Composite key for `.task(id:)`. The cache must invalidate on either a
    /// new issue (covered by `.id(issue.id)` for the view subtree, but the
    /// task fires before that takes effect) or an in-place edit detected by
    /// FSEvents bumping `modifiedAt`.
    private var parseCacheKey: String {
        "\(issue.id)|\(issue.modifiedAt.timeIntervalSinceReferenceDate)"
    }
}

/// Cached parse of an issue's markdown body. Stored as `@State` on
/// `DetailPanelDescriptionView` so the disk read and chunk split happen once
/// per `(issue.id, modifiedAt)` rather than once per body recompute (#0072).
private struct ParsedBody: Equatable {
    let issueID: String
    let modifiedAt: Date
    /// The raw body markdown (everything from the first `## ` onward) or
    /// `nil` when the file can't be read or contains no H2 — callers fall
    /// back to a plain `Text` view in that case.
    let body: String?
    /// Pre-split image / prose chunks. `body == nil` ⇒ empty.
    let chunks: [InlineImageMarkdown.Chunk]

    /// Sentinel used as the initial `@State` value before the first
    /// `.task(id:)` fires. The empty `issueID` keeps it from accidentally
    /// matching a real issue's cache key.
    static let empty = ParsedBody(
        issueID: "",
        modifiedAt: .distantPast,
        body: nil,
        chunks: []
    )

    static func load(from issue: Issue) -> ParsedBody {
        let body = Self.bodyMarkdown(at: issue.fileURL)
        let chunks: [InlineImageMarkdown.Chunk] = {
            guard let body else { return [] }
            return InlineImageMarkdown.split(IssueCrossRef.rewrite(body))
        }()
        return ParsedBody(
            issueID: issue.id,
            modifiedAt: issue.modifiedAt,
            body: body,
            chunks: chunks
        )
    }

    /// Returns the markdown body below the H1 title and metadata table,
    /// starting at the first H2 (`## `). Returns nil if the file can't be
    /// read or no H2 is found, so callers can fall back to plain text.
    private static func bodyMarkdown(at url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        guard let range = raw.range(of: "\n## ") else {
            return nil
        }
        // Include the H2 marker itself; drop the leading newline.
        let body = raw[range.lowerBound...].dropFirst()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Renders the parsed body chunks as an ordered stack of prose
/// (`StructuredText`) and images (`AttachmentThumbnailView`). Conforms to
/// `Equatable` keyed on `(issueID, modifiedAt, body, baseURL)` so
/// `EquatableView` short-circuits the rebuild when only an upstream non-
/// content state changes — most importantly the detail-panel `panelWidth`
/// from #0069, which fires on every frame of a resize drag and used to
/// flicker the rendered prose (#0072). Callbacks are intentionally excluded
/// from equality: they're recreated on every parent body call but their
/// *behavior* doesn't depend on width, so treating them as equal is safe and
/// is the whole point of the short-circuit.
private struct BodyView: View, Equatable {
    let issueID: String
    let modifiedAt: Date
    /// Raw body markdown — used only for the equality fingerprint. The chunks
    /// are derived from this string upstream and are what actually drives the
    /// rendered subtree.
    let bodyText: String
    let baseURL: URL
    let chunks: [InlineImageMarkdown.Chunk]
    let onOpenIssue: ((String) -> Void)?
    let onOpenAttachment: (URL) -> Void
    let onPlayVideo: (URL) -> Void

    static func == (lhs: BodyView, rhs: BodyView) -> Bool {
        // Identity + content fingerprint is enough — the chunks list is a
        // pure function of `bodyText`, and the callbacks are width-independent.
        lhs.issueID == rhs.issueID
            && lhs.modifiedAt == rhs.modifiedAt
            && lhs.bodyText == rhs.bodyText
            && lhs.baseURL == rhs.baseURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case .prose(let markdown):
                    StructuredText(
                        markdown: markdown,
                        baseURL: baseURL
                    )
                    .textual.textSelection(.enabled)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        // Intercept the custom `issue://NNNN` scheme and
                        // route it back to the host. Everything else (https,
                        // mailto, file) falls through to the system handler
                        // so external links keep working.
                        if let id = IssueCrossRef.issueID(from: url) {
                            onOpenIssue?(id)
                            return .handled
                        }
                        return .systemAction
                    })
                case .image(let alt, let path, let linkPath):
                    AttachmentThumbnailView(
                        alt: alt,
                        path: path,
                        baseURL: baseURL,
                        videoPath: linkPath,
                        onOpen: onOpenAttachment,
                        onPlay: onPlayVideo
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        DetailPanelDescriptionView(issue: PreviewSamples.issue)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        DetailPanelDescriptionView(issue: PreviewSamples.issue)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    DetailPanelDescriptionView(issue: PreviewSamples.issue)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DetailPanelDescriptionView(issue: PreviewSamples.issue)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
