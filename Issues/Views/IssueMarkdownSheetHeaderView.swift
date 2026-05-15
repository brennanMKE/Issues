import SwiftUI
import IssuesCore

struct IssueMarkdownSheetHeaderView: View {
    let issue: Issue
    var searchQuery: String = ""
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(issue.id) \u{2014} \(issue.title)", highlighting: searchQuery)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(issue.fileURL.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appBackgroundCard)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        IssueMarkdownSheetHeaderView(issue: PreviewSamples.issue, onDismiss: {})
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        IssueMarkdownSheetHeaderView(issue: PreviewSamples.issue, onDismiss: {})
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    IssueMarkdownSheetHeaderView(issue: PreviewSamples.issue, onDismiss: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    IssueMarkdownSheetHeaderView(issue: PreviewSamples.issue, onDismiss: {})
        .preferredColorScheme(.dark)
}
#endif
