import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    init(hex: String) {
        let trimmed = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let r, g, b, a: Double
        switch trimmed.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
            a = 1.0
        case 8:
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >> 8) & 0xFF) / 255.0
            a = Double(value & 0xFF) / 255.0
        default:
            r = 0
            g = 0
            b = 0
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Adaptive color that resolves to `light` in Aqua and `dark` in Dark Aqua.
    /// Wraps `NSColor(name:dynamicProvider:)` so the value re-evaluates whenever
    /// the system appearance changes.
    init(light: Color, dark: Color) {
        #if canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }

    static let appBackground = Color(
        light: Color(hex: "#ffffff"),
        dark: Color(hex: "#0d1117")
    )
    static let appBackgroundCard = Color(
        light: Color(hex: "#f5f5f7"),
        dark: Color(hex: "#161b22")
    )
    static let appBackgroundHover = Color(
        light: Color(hex: "#ebebed"),
        dark: Color(hex: "#1c2230")
    )
    static let appBorder = Color(
        light: Color(hex: "#d2d2d4"),
        dark: Color(hex: "#30363d")
    )
    static let appText = Color(
        light: Color(hex: "#0a0a0f"),
        dark: Color(hex: "#e6edf3")
    )
    static let appMuted = Color(
        light: Color(hex: "#6b7280"),
        dark: Color(hex: "#8b949e")
    )
    static let appAccent = Color.accentColor
    static let appAccentDim = Color.accentColor.opacity(0.6)

    static let statusOpen = Color(hex: "#f59e0b")
    static let statusInProgress = Color(hex: "#3b82f6")
    static let statusResolved = Color(hex: "#10b981")
    static let statusClosed = Color(hex: "#6b7280")
    static let statusWontfix = Color(hex: "#ef4444")
}
