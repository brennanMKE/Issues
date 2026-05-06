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

#Preview {
    ShortcutsSettingsView()
        .frame(width: 520, height: 480)
}
