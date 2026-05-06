import SwiftUI

/// Shortcuts pane: one row per `ShortcutAction`, each with a recorder and a
/// per-row reset button. Surfaces collisions and reserved-shortcut conflicts
/// inline beneath the offending row. See #0024.
struct ShortcutsSettingsView: View {
    @State private var store = AppCommandsController.shared.shortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRow(action: action, store: store)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Reset All to Defaults") {
                    store.resetAllToDefaults()
                }
            }
        }
        .padding()
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        ShortcutsSettingsView()
            .frame(width: 520, height: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        ShortcutsSettingsView()
            .frame(width: 520, height: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    ShortcutsSettingsView()
        .frame(width: 520, height: 480)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ShortcutsSettingsView()
        .frame(width: 520, height: 480)
        .preferredColorScheme(.dark)
}
#endif
