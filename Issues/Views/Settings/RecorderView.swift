import SwiftUI
import AppKit
import Carbon.HIToolbox

/// AppKit recorder. Public-ish so `KeyboardShortcutRecorder` can hand-construct it.
final class RecorderView: NSView {
    var binding: ShortcutBinding = ShortcutBinding(key: "", modifiers: 0) {
        didSet { needsDisplay = true }
    }
    var onCommit: ((ShortcutBinding) -> Void)?

    private var isRecording: Bool = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 110, height: KeyboardShortcutRecorder.preferredHeight)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Clicking the recorder explicitly transfers first-responder. SwiftUI
        // doesn't do this automatically for raw `NSView`s wrapped via
        // `NSViewRepresentable`, so without this `keyDown:` never fires.
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            isRecording = true
            needsDisplay = true
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            isRecording = false
            needsDisplay = true
        }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Esc cancels recording without clearing the binding. Dropping first
        // responder triggers `resignFirstResponder`, which flips `isRecording`
        // back off and redraws the idle state.
        if Int(event.keyCode) == kVK_Escape {
            window?.makeFirstResponder(nil)
            return
        }

        let mods = eventModifiers(from: event.modifierFlags)
        guard let candidate = makeBinding(from: event, modifiers: mods) else {
            // Couldn't translate (e.g. dead key) — swallow rather than passing
            // through to avoid beep + accidental text insertion.
            NSSound.beep()
            return
        }

        onCommit?(candidate)
        binding = candidate
        // Drop focus so the visual returns to idle. `resignFirstResponder`
        // clears `isRecording`.
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 5, yRadius: 5)

        // Background.
        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        // Border.
        if isRecording {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1.0
        }
        path.stroke()

        // Label text.
        let label: String
        let color: NSColor
        if isRecording {
            label = "Press a shortcut\u{2026}"
            color = NSColor.secondaryLabelColor
        } else if binding.key.isEmpty {
            label = "Click to record"
            color = NSColor.tertiaryLabelColor
        } else {
            label = binding.displayString
            color = NSColor.labelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: label, attributes: attrs)
        let textSize = attributed.size()
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }

    // MARK: - Event translation

    private func eventModifiers(from flags: NSEvent.ModifierFlags) -> SwiftUI.EventModifiers {
        // Carbon also defines a typealias `EventModifiers`; qualify with
        // `SwiftUI.` so the compiler picks the right one.
        var mods: SwiftUI.EventModifiers = []
        if flags.contains(.command)  { mods.insert(.command) }
        if flags.contains(.option)   { mods.insert(.option) }
        if flags.contains(.shift)    { mods.insert(.shift) }
        if flags.contains(.control)  { mods.insert(.control) }
        // .function intentionally dropped — reserved for system use as of macOS 12.
        return mods
    }

    private func makeBinding(from event: NSEvent, modifiers: SwiftUI.EventModifiers) -> ShortcutBinding? {
        // Map common special keys by keyCode first (independent of layout).
        if let special = specialKey(forKeyCode: Int(event.keyCode)) {
            return ShortcutBinding(key: special.rawValue, modifiers: modifiers.rawValue)
        }

        // Plain character keys: require at least one non-shift modifier so the
        // user can't bind `t` and shadow text input.
        let nonShiftMods: SwiftUI.EventModifiers = modifiers.subtracting([.shift])
        guard !nonShiftMods.isEmpty else {
            return nil
        }

        guard let chars = event.charactersIgnoringModifiers, let first = chars.first else {
            return nil
        }
        // Lowercase so `Cmd+T` and `Cmd+Shift+T` share the same `t` key field;
        // shift state lives in modifiers.
        let key = String(first).lowercased()
        return ShortcutBinding(key: key, modifiers: modifiers.rawValue)
    }

    private func specialKey(forKeyCode keyCode: Int) -> ShortcutBinding.SpecialKey? {
        switch keyCode {
        case kVK_LeftArrow:  return .leftArrow
        case kVK_RightArrow: return .rightArrow
        case kVK_UpArrow:    return .upArrow
        case kVK_DownArrow:  return .downArrow
        case kVK_Return:     return .return
        case kVK_Tab:        return .tab
        case kVK_Space:      return .space
        case kVK_Delete:     return .delete
        default:             return nil
        }
    }
}
