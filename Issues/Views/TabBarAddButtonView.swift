import SwiftUI

/// Trailing "+" button on the tab bar. Opens the dedicated folder-picker
/// scene (#0029) rather than calling `presentOpenPanel()` directly so users
/// see the remembered-folders list before falling through to NSOpenPanel.
struct TabBarAddButtonView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "folderPicker")
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appText)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Open another folder in a new tab")
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        TabBarAddButtonView()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        TabBarAddButtonView()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TabBarAddButtonView()
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TabBarAddButtonView()
        .padding()
        .preferredColorScheme(.dark)
}
#endif
