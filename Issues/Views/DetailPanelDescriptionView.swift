import SwiftUI
import Textual

struct DetailPanelDescriptionView: View {
    let issue: Issue
    /// Optional callback invoked when the user clicks a `#NNNN` cross-
    /// reference link inside the markdown body (#0054). The argument is the
    /// four-digit id parsed out of the `issue://NNNN` URL. When `nil`, the
    /// click no-ops cleanly — previews and standalone hosts that don't have a
    /// store don't crash.
    var onOpenIssue: ((String) -> Void)? = nil

    /// File URL of an attachment the user clicked (#0056). Drives a sheet
    /// presentation so the host doesn't have to track per-thumbnail state. Set
    /// to nil to dismiss.
    @State private var attachmentURL: URL?

    var body: some View {
        Group {
            if let body = bodyMarkdown() {
                bodyView(for: body)
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
        .sheet(isPresented: Binding(
            get: { attachmentURL != nil },
            set: { if !$0 { attachmentURL = nil } }
        )) {
            if let url = attachmentURL {
                AttachmentSheet(url: url)
            }
        }
    }

    /// Renders the body as an ordered stack of prose chunks (via
    /// `StructuredText`) and image chunks (via `AttachmentThumbnailView`).
    /// Splitting happens because `Canvas`-drawn Textual attachments don't
    /// receive gesture hits — see `InlineImageMarkdown` for the rationale.
    @ViewBuilder
    private func bodyView(for body: String) -> some View {
        let chunks = InlineImageMarkdown.split(IssueCrossRef.rewrite(body))
        let baseURL = issue.fileURL.deletingLastPathComponent()
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
                case .image(let alt, let path):
                    AttachmentThumbnailView(
                        alt: alt,
                        path: path,
                        baseURL: baseURL,
                        onOpen: { attachmentURL = $0 }
                    )
                }
            }
        }
    }

    /// Returns the markdown body below the H1 title and metadata table,
    /// starting at the first H2 (`## `). Returns nil if the file can't be
    /// read or no H2 is found, so callers can fall back to plain text.
    private func bodyMarkdown() -> String? {
        guard let raw = try? String(contentsOf: issue.fileURL, encoding: .utf8) else {
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
