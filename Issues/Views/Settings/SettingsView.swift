import SwiftUI

/// Top-level container for the macOS native Settings scene. Hosted by
/// `IssuesApp`'s `Settings { ... }` block (#0024).
///
/// Uses the system default `TabView` style so it picks up the toolbar-tab look
/// macOS users expect from a preferences window.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(minWidth: 520, minHeight: 420)
        .scenePadding()
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        SettingsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        SettingsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    SettingsView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView()
        .preferredColorScheme(.dark)
}
#endif
