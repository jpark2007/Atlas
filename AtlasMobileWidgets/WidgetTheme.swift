import SwiftUI

/// Editorial Minimal tokens for the widget extension — a small mirror of the app's
/// MobileTheme (which lives in the app target and can't be linked here). Same
/// palette, same rule: clay is for NOW / live only.
enum WidgetTheme {
    static let bg      = Color(hex: "f2efe6")
    static let ink     = Color(hex: "211d17")
    static let muted   = Color(hex: "565145")
    static let faint   = Color(hex: "7d7669")
    static let hairline = Color(hex: "211d17").opacity(0.12)
    static let accent     = Color(hex: "d97757")
    static let accentText = Color(hex: "b04f2f")
}

extension Color {
    /// Hex → Color (RRGGBB), mirrors AtlasCore's initializer for the extension.
    init(hex: String) {
        let s = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        s.scanHexInt64(&rgb)
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1)
    }
}
