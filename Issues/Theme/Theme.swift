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

    // The named palette colors (`appBackground`, `statusOpen`, etc.) are provided
    // automatically by Xcode's generated asset symbols from `Assets.xcassets/`.
    // Only the derived accent helpers need to be declared here.
    static let appAccent           = Color.accentColor
    static let appAccentDim        = Color.accentColor.opacity(0.6)
}
