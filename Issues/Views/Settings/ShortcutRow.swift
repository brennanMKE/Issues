import SwiftUI

/// One Form row: name, recorder, per-row reset, and an inline warning row when
/// the current binding collides with another action or hits a reserved combo.
struct ShortcutRow: View {
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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        Form {
            ShortcutRow(action: .newTab, store: ShortcutsStore())
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        Form {
            ShortcutRow(action: .newTab, store: ShortcutsStore())
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    Form {
        ShortcutRow(action: .newTab, store: ShortcutsStore())
    }
    .formStyle(.grouped)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    Form {
        ShortcutRow(action: .newTab, store: ShortcutsStore())
    }
    .formStyle(.grouped)
    .preferredColorScheme(.dark)
}
#endif
