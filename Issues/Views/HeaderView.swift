import SwiftUI

struct HeaderView: View {
    let folderURL: URL
    let onSwitchFolder: () -> Void

    private var repoName: String {
        folderURL.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(repoName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text("\u{2014}")
                    .foregroundStyle(Color.appMuted)
                Text("Issues")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            Spacer()
            Text(folderURL.path)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Switch folder\u{2026}", action: onSwitchFolder)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 1)
        }
    }
}
