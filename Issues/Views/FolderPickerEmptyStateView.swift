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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        FolderPickerEmptyStateView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        FolderPickerEmptyStateView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    FolderPickerEmptyStateView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FolderPickerEmptyStateView()
        .preferredColorScheme(.dark)
}
#endif
