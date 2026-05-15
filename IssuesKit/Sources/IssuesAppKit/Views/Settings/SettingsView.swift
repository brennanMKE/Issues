import SwiftUI
import IssuesCore

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

            #if os(macOS)
            RemoteAccessSettingsTab()
                .tabItem {
                    Label("Remote Access", systemImage: "antenna.radiowaves.left.and.right")
                }
            #endif
        }
        .frame(minWidth: 520, minHeight: 420)
        .scenePadding()
    }
}

#if os(macOS)
/// Bridge between the Settings scene and the `RemoteHostController` owned by
/// `RootView`. The controller lives on the main window's view tree, so this
/// tab reads it back through `AppCommandsController.shared` (the same
/// indirection pattern the menu commands use). Until the main window mounts
/// for the first time, the tab shows a small placeholder.
private struct RemoteAccessSettingsTab: View {
    @State private var commands = AppCommandsController.shared

    var body: some View {
        Group {
            if let controller = commands.hostController {
                RemoteHostSettingsView(controller: controller)
            } else {
                Text("Open the main window to access remote hosting settings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            }
        }
    }
}
#endif

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
