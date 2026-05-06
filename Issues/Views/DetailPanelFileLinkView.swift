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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        DetailPanelFileLinkView(issue: PreviewSamples.issue, onOpenMarkdown: { _ in })
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        DetailPanelFileLinkView(issue: PreviewSamples.issue, onOpenMarkdown: { _ in })
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    DetailPanelFileLinkView(issue: PreviewSamples.issue, onOpenMarkdown: { _ in })
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DetailPanelFileLinkView(issue: PreviewSamples.issue, onOpenMarkdown: { _ in })
        .padding()
        .preferredColorScheme(.dark)
}
#endif
