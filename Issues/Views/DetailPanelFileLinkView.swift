import SwiftUI

struct DetailPanelFileLinkView: View {
    let issue: Issue
    let onOpenMarkdown: (Issue) -> Void

    var body: some View {
        Button {
            onOpenMarkdown(issue)
        } label: {
            HStack(spacing: 4) {
                Text("\(issue.id).md")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.appAccent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Preview \(issue.fileURL.lastPathComponent)")
    }
}
