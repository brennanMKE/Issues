import SwiftUI
import Textual

struct IssueMarkdownSheetContentView: View {
    let issue: Issue

    var body: some View {
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
