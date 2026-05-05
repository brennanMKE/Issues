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

#Preview {
    SettingsView()
}
