import SwiftUI
import Textual

struct DetailPanelDescriptionView: View {
    let issue: Issue

    var body: some View {
        Group {
            if let body = bodyMarkdown() {
                StructuredText(
                    markdown: body,
                    baseURL: issue.fileURL.deletingLastPathComponent()
                )
                .textual.textSelection(.enabled)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
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
