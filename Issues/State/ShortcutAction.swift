import SwiftUI

/// The catalog of user-configurable keyboard shortcuts. Cmd+1…9 (tab activation),
/// arrow-key list navigation, and Esc are intentionally *not* in this list — they
/// stay fixed (see #0024 "Stays fixed" section).
///
/// Each case is identified by a stable `id` string used as the persistence key
/// in `UserDefaults`. Renaming a case mid-flight would orphan a saved binding;
/// keep the `id` mapping append-only.
enum ShortcutAction: String, CaseIterable, Hashable, Identifiable {
    case previousTab
    case nextTab
    case newTab
    case closeTab
    case reload
    case focusSearch
    case swimlanesView
    case timelineView
    case listView
    case recentView

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .previousTab:    return "Show Previous Tab"
        case .nextTab:        return "Show Next Tab"
        case .newTab:         return "New Tab"
        case .closeTab:       return "Close Tab"
        case .reload:         return "Reload"
        case .focusSearch:    return "Find / Focus Search"
        case .swimlanesView:  return "Swimlanes View"
        case .timelineView:   return "Timeline View"
        case .listView:       return "List View"
        case .recentView:     return "Recent View"
        }
    }

    /// Default binding shipped in #0008. Restored by "Reset" in the Shortcuts pane.
    var defaultBinding: ShortcutBinding {
        switch self {
        case .previousTab:
            return ShortcutBinding(key: ShortcutBinding.SpecialKey.leftArrow.rawValue,
                                   modifiers: EventModifiers([.command, .shift]).rawValue)
        case .nextTab:
            return ShortcutBinding(key: ShortcutBinding.SpecialKey.rightArrow.rawValue,
                                   modifiers: EventModifiers([.command, .shift]).rawValue)
        case .newTab:
            return ShortcutBinding(key: "t", modifiers: EventModifiers([.command]).rawValue)
        case .closeTab:
            return ShortcutBinding(key: "w", modifiers: EventModifiers([.command]).rawValue)
        case .reload:
            return ShortcutBinding(key: "r", modifiers: EventModifiers([.command]).rawValue)
        case .focusSearch:
            return ShortcutBinding(key: "f", modifiers: EventModifiers([.command]).rawValue)
        case .swimlanesView:
            return ShortcutBinding(key: "1", modifiers: EventModifiers([.command, .option]).rawValue)
        case .timelineView:
            return ShortcutBinding(key: "2", modifiers: EventModifiers([.command, .option]).rawValue)
        case .listView:
            return ShortcutBinding(key: "3", modifiers: EventModifiers([.command, .option]).rawValue)
        case .recentView:
            return ShortcutBinding(key: "4", modifiers: EventModifiers([.command, .option]).rawValue)
        }
    }
}
