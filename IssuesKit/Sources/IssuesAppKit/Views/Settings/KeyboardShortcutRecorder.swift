import SwiftUI
import IssuesCore

/// A focusable, click-to-record keyboard shortcut field for the Settings pane.
///
/// Idle: shows the formatted current binding (`⌘⇧→`) inside a bordered button.
/// Recording: focused state shows `"Press a shortcut…"` with a tinted ring;
/// the next non-modifier `keyDown` is converted to a `ShortcutBinding` and
/// written back through `binding`. Esc cancels recording (does not clear the
/// binding).
///
/// Implementation notes:
/// - Uses a custom `NSView` subclass rather than `NSTextField`. The text-field
///   path requires fighting the field editor; a plain focusable view that
///   overrides `keyDown(with:)` is cleaner and lets us draw our own focus ring.
/// - The recorder rejects events with no modifier keys for non-special keys
///   (e.g. plain `t`) — those would shadow normal typing. Special keys
///   (arrow, return, etc.) are accepted bare since they're already non-text.
struct KeyboardShortcutRecorder: NSViewRepresentable {
    @Binding var binding: ShortcutBinding

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.binding = binding
        view.onCommit = { newBinding in
            // Hop out of the AppKit event path before mutating SwiftUI state.
            Task { @MainActor in
                self.binding = newBinding
            }
        }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.binding = binding
        nsView.needsDisplay = true
    }

    /// Fixed control height keeps `Form` rows aligned.
    static var preferredHeight: CGFloat { 24 }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        KeyboardShortcutRecorder(binding: .constant(ShortcutBinding(key: "t", modifiers: EventModifiers([.command]).rawValue)))
            .frame(width: 130, height: KeyboardShortcutRecorder.preferredHeight)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        KeyboardShortcutRecorder(binding: .constant(ShortcutBinding(key: "t", modifiers: EventModifiers([.command]).rawValue)))
            .frame(width: 130, height: KeyboardShortcutRecorder.preferredHeight)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    KeyboardShortcutRecorder(binding: .constant(ShortcutBinding(key: "t", modifiers: EventModifiers([.command]).rawValue)))
        .frame(width: 130, height: KeyboardShortcutRecorder.preferredHeight)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    KeyboardShortcutRecorder(binding: .constant(ShortcutBinding(key: "t", modifiers: EventModifiers([.command]).rawValue)))
        .frame(width: 130, height: KeyboardShortcutRecorder.preferredHeight)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
