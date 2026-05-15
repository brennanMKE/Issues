import SwiftUI
import IssuesCore

public extension Color {
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

    // The named palette colors live in the *app target's* `Assets.xcassets/`
    // (per #0134: AppIcon must stay in the app target's catalog, and we
    // keep all colors next to AppIcon). Xcode's generated asset symbols are
    // therefore emitted into the app target's module, not into this package.
    // We re-expose them here as explicit `Color("name", bundle: .main)`
    // lookups so package-side views can keep writing `Color.appBackground`
    // unchanged. `Bundle.main` resolves to the app bundle at runtime.
    static let appBackground       = Color("appBackground",       bundle: .main)
    static let appBackgroundCard   = Color("appBackgroundCard",   bundle: .main)
    static let appBackgroundHover  = Color("appBackgroundHover",  bundle: .main)
    static let appBorder           = Color("appBorder",           bundle: .main)
    static let appMuted            = Color("appMuted",            bundle: .main)
    static let appText             = Color("appText",             bundle: .main)
    static let accentForeground    = Color("accentForeground",    bundle: .main)

    static let statusOpen          = Color("statusOpen",          bundle: .main)
    static let statusInProgress    = Color("statusInProgress",    bundle: .main)
    static let statusResolved      = Color("statusResolved",      bundle: .main)
    static let statusClosed        = Color("statusClosed",        bundle: .main)
    static let statusWontfix       = Color("statusWontfix",       bundle: .main)

    static let appAccent           = Color.accentColor
    static let appAccentDim        = Color.accentColor.opacity(0.6)
}
