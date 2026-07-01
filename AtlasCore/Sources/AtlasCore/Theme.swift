import SwiftUI

/// Atlas design tokens — extracted from the approved dark prototype.
public enum AtlasTheme {
    public enum Colors {
        // Warm near-black backgrounds (deepest → most elevated)
        public static let bgDeep      = Color(hex: "100e0c")
        public static let bgBase      = Color(hex: "16130f")
        public static let bgSidebar   = Color(hex: "1a140f")
        public static let bgCard      = Color(hex: "1c1814")
        public static let bgElevated  = Color(hex: "211d18")

        public static let border      = Color.white.opacity(0.06)
        public static let borderStrong = Color.white.opacity(0.10)

        // Text
        public static let textPrimary   = Color(hex: "f3ede4")
        public static let textSecondary = Color(hex: "a89b8a")
        public static let textMuted     = Color(hex: "6f655a")

        // Brand accent
        public static let accent     = Color(hex: "ff8c42")
        public static let accentDeep = Color(hex: "ff6b1a")

        // Semantic status tokens
        public static let warning  = Color(hex: "febc2e") // warm amber
        public static let danger   = Color(hex: "ff5c5c") // warm red

        // Space identity colors
        public static let school   = Color(hex: "5b9bd5")
        public static let personal = Color(hex: "5fb98e")
        public static let side     = Color(hex: "b48ad9")
        public static let yellow   = Color(hex: "febc2e")
        public static let green    = Color(hex: "5fb98e")
    }

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let card: CGFloat = 14
    }

    public enum Font {
        public static func kicker() -> SwiftUI.Font { .system(size: 11, weight: .semibold) }
        public static func sectionLabel() -> SwiftUI.Font { .system(size: 11, weight: .semibold) }
        public static func greeting() -> SwiftUI.Font { .system(size: 28, weight: .semibold) }
        public static func cardTitle() -> SwiftUI.Font { .system(size: 14, weight: .semibold) }
        public static func body() -> SwiftUI.Font { .system(size: 13, weight: .regular) }
        public static func bodyMedium() -> SwiftUI.Font { .system(size: 13, weight: .medium) }
        public static func small() -> SwiftUI.Font { .system(size: 11, weight: .regular) }
    }
}

/// A standard Atlas content card.
public struct AtlasCard<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AtlasTheme.Colors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1)
            )
    }
}

extension Color {
    public init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
