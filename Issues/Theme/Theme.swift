import SwiftUI

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

    static let appBackground = Color(hex: "#0d1117")
    static let appBackgroundCard = Color(hex: "#161b22")
    static let appBackgroundHover = Color(hex: "#1c2230")
    static let appBorder = Color(hex: "#30363d")
    static let appText = Color(hex: "#e6edf3")
    static let appMuted = Color(hex: "#8b949e")
    static let appAccent = Color.accentColor
    static let appAccentDim = Color.accentColor.opacity(0.6)

    static let statusOpen = Color(hex: "#f59e0b")
    static let statusInProgress = Color(hex: "#3b82f6")
    static let statusResolved = Color(hex: "#10b981")
    static let statusClosed = Color(hex: "#6b7280")
    static let statusWontfix = Color(hex: "#ef4444")
}
