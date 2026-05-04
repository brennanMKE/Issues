import SwiftUI
import Textual

struct IssueMarkdownSheet: View {
    let issue: Issue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.appBorder)
            contentBody
        }
        .frame(width: 720, height: 800)
        .frame(minWidth: 480, minHeight: 400)
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(issue.id) \u{2014} \(issue.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(issue.fileURL.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            Spacer(minLength: 8)
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appBackgroundCard)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch loadMarkdown() {
        case .success(let text):
            ScrollView(.vertical) {
                StructuredText(
                    markdown: text,
                    baseURL: issue.fileURL.deletingLastPathComponent()
                )
                .textual.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.appBackground)
        case .failure(let error):
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't read \(issue.fileURL.lastPathComponent)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.appBackground)
        }
    }

    private func loadMarkdown() -> Result<String, Error> {
        do {
            let text = try String(contentsOf: issue.fileURL, encoding: .utf8)
            return .success(text)
        } catch {
            return .failure(error)
        }
    }
}
