import SwiftUI

struct FolderPickerEmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(Color.appMuted)
            Text("No remembered folders yet.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.vertical, 12)
    }
}
