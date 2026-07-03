import SwiftUI

/// Atlas design tokens — Editorial Minimal · LIGHT · clay.
/// Remapped from the dark prototype to the mobile light system
/// (`AtlasMobile/Theme/MobileTheme.swift` is the source of truth).
/// RULES: accent = live/NOW/brand graphics ONLY, never a button fill.
/// Controls are transparent with 1.5 pt ink outlines. No card chrome —
/// content sits on the cream bg, sections separate with black-8% hairlines.
public enum AtlasTheme {

    /// Strong ink rule (header underlines, outlined controls, hairline separators).
    public static let rule: CGFloat = 1.5

    public enum Colors {
        // Cream backgrounds (recessed → most elevated). Card/elevated tints are
        // near-invisible — content reads as sitting on the bg, not on chrome.
        public static let bgDeep      = Color(hex: "f3f1ec") // recessed
        public static let bgBase      = Color(hex: "fbfaf7")
        public static let bgSidebar   = Color(hex: "f7f5f0")
        public static let bgCard      = Color(hex: "faf8f4") // cream tint, near-invisible
        public static let bgElevated  = Color(hex: "f8f6f1") // cream tint, near-invisible

        public static let border       = Color.black.opacity(0.08)
        public static let borderStrong = Color.black.opacity(0.14)

        /// The editorial section separator (black 8%).
        public static let hairline = Color.black.opacity(0.08)

        // Text
        public static let textPrimary   = Color(hex: "1a191d")
        public static let textSecondary = Color(hex: "6c6a72")
        public static let textMuted      = Color(hex: "9a98a0")

        // Brand accent — clay. Graphics only (NOW / live / brand). Never a fill.
        public static let accent     = Color(hex: "d97757")
        public static let accentDeep = Color(hex: "b04f2f")
        /// Darkened accent for TEXT on light surfaces (AA).
        public static let accentText = Color(hex: "b04f2f")

        // Semantic status tokens
        public static let warning  = Color(hex: "febc2e") // warm amber
        public static let danger   = Color(hex: "ff5c5c") // warm red

        // Space identity colors — hue kept; used as dots/fills on cream.
        public static let school   = Color(hex: "5b9bd5")
        public static let personal = Color(hex: "5fb98e")
        public static let side     = Color(hex: "b48ad9")
        public static let yellow   = Color(hex: "febc2e")
        public static let green    = Color(hex: "5fb98e")
    }

    /// Continuous-corner radii at Mac density.
    public enum Radius {
        public static let sm: CGFloat  = 10 // chip
        public static let md: CGFloat  = 14 // control
        public static let lg: CGFloat  = 18 // card
        public static let card: CGFloat    = 18
        public static let control: CGFloat = 14
        public static let chip: CGFloat    = 10
    }

    public enum Font {
        public static func kicker() -> SwiftUI.Font { .system(size: 11, weight: .semibold, design: .rounded) }
        public static func sectionLabel() -> SwiftUI.Font { .system(size: 11, weight: .semibold, design: .rounded) }
        public static func greeting() -> SwiftUI.Font { .system(size: 28, weight: .semibold, design: .rounded) }
        public static func cardTitle() -> SwiftUI.Font { .system(size: 14, weight: .semibold, design: .rounded) }
        public static func body() -> SwiftUI.Font { .system(size: 13, weight: .regular, design: .rounded) }
        public static func bodyMedium() -> SwiftUI.Font { .system(size: 13, weight: .medium, design: .rounded) }
        public static func small() -> SwiftUI.Font { .system(size: 11, weight: .regular, design: .rounded) }
    }
}

/// A standard Atlas content section — no chrome. Padding + a hairline rule along
/// the bottom edge separates it from the next section (editorial, not carded).
public struct AtlasCard<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtlasTheme.Colors.hairline)
                    .frame(height: 1)
            }
    }
}

// MARK: - Reusable editorial view modifiers
//
// Ported from AtlasMobile with `atlas-` prefixed names (the mobile `ed-` names
// stay in AtlasMobile — declaring same-signature extensions in two visible
// modules would make mobile call sites ambiguous). Pure SwiftUI, no UIKit/AppKit:
// this package builds for both platforms.

extension View {
    /// Big editorial screen title — 31 / heavy, −0.03em tracking, ink.
    public func atlasScreenTitle() -> some View {
        self
            .font(.system(size: 31, weight: .heavy, design: .rounded))
            .tracking(-0.93)            // −0.03em × 31
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
    }

    /// Small uppercase caps label — 11 / bold, +0.08em tracking, muted.
    public func atlasCapsLabel() -> some View {
        self
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.88)             // +0.08em × 11
            .textCase(.uppercase)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
    }

    /// Transparent control with a 1.5 pt ink outline, control radius (14).
    public func atlasOutlineControl() -> some View {
        self
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
            )
            .contentShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous))
    }

    /// Hairline rule (black 8%) along the bottom edge — the editorial row separator.
    public func atlasHairlineBelow() -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtlasTheme.Colors.hairline)
                .frame(height: 1)
        }
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
