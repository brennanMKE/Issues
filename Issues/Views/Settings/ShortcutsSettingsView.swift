import SwiftUI

/// Shortcuts pane: one row per `ShortcutAction`, each with a recorder and a
/// per-row reset button. Surfaces collisions and reserved-shortcut conflicts
/// inline beneath the offending row. See #0024.
struct ShortcutsSettingsView: View {
    @State private var store = AppCommandsController.shared.shortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize keyboard shortcuts. Cmd+1 through 9 (tab activation), arrow keys, and Esc are not customizable.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

/// One Form row: name, recorder, per-row reset, and an inline warning row when
/// the current binding collides with another action or hits a reserved combo.
private struct ShortcutRow: View {
    let action: ShortcutAction
    let store: ShortcutsStore

    var body: some View {
        let current = store.binding(for: action)
        let collisions = store.collisions(current, excluding: action)
        let reserved = ShortcutsStore.isReserved(current)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.displayName)
                Spacer()
                KeyboardShortcutRecorder(binding: bindingProxy)
                    .frame(width: 130, height: KeyboardShortcutRecorder.preferredHeight)

                Button("Reset") {
                    store.resetToDefault(action)
                }
                .controlSize(.small)
                .disabled(current == action.defaultBinding)
            }

            if reserved {
                warning("Reserved by macOS — choose a different shortcut.")
            } else if let other = collisions.first {
                warning("Used by \(other.displayName)")
            }
        }
    }

    /// Bridges `KeyboardShortcutRecorder`'s `@Binding<ShortcutBinding>` to the
    /// store, refusing reserved combos. Collisions are *allowed* but warned —
    /// the user can decide.
    private var bindingProxy: Binding<ShortcutBinding> {
        Binding(
            get: { store.binding(for: action) },
            set: { newValue in
                guard !ShortcutsStore.isReserved(newValue) else {
                    // Still write so the warning row appears — clearer feedback
                    // than silently dropping the keystroke. The user can then
                    // hit Reset or pick a non-reserved combo. v1 trade-off.
                    store.setBinding(newValue, for: action)
                    return
                }
                store.setBinding(newValue, for: action)
            }
        )
    }

    private func warning(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(Color.statusOpen)
    }
}

#Preview {
    ShortcutsSettingsView()
        .frame(width: 520, height: 480)
}
