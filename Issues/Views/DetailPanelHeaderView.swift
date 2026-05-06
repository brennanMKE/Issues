import SwiftUI

struct DetailPanelHeaderView: View {
    let issue: Issue
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(issue.id)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.appMuted)
                Text(issue.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.appMuted)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        DetailPanelHeaderView(issue: PreviewSamples.issue, onClose: {})
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        DetailPanelHeaderView(issue: PreviewSamples.issue, onClose: {})
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    DetailPanelHeaderView(issue: PreviewSamples.issue, onClose: {})
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DetailPanelHeaderView(issue: PreviewSamples.issue, onClose: {})
        .padding()
        .preferredColorScheme(.dark)
}
#endif
