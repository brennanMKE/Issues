import SwiftUI

/// Top-of-window title strip. With the tab bar (issue #0002) the active repo
/// name now appears on its tab chip, so the header just shows the app title
/// and the active folder's path on the trailing side. The previous
/// "Switch folder…" button was removed because adding a tab supersedes it.
struct HeaderView: View {
    let folderURL: URL

    var body: some View {
        HStack(spacing: 12) {
            Text("Issues")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            Spacer()
            Text(folderURL.path)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .lineLimit(1)
                .truncationMode(.middle)
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
