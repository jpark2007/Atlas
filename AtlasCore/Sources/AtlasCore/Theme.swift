import SwiftUI

public struct AtlasTextScaleKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// Global user-adjustable text scale, set once at the app root from
    /// `@AppStorage("appearance.textScale")` (see `AtlasApp.swift`). Every
    /// font in the Mac app should render through `atlasFont` so it responds
    /// to this value — see that function for the single choke point.
    public var atlasTextScale: CGFloat {
        get { self[AtlasTextScaleKey.self] }
        set { self[AtlasTextScaleKey.self] = newValue }
    }
}

/// Atlas design tokens — Editorial Minimal · LIGHT · clay.
/// Remapped from the dark prototype to the mobile light system
/// (`AtlasMobile/Theme/MobileTheme.swift` is the source of truth).
/// RULES: accent = live/NOW/brand graphics ONLY, never a button fill.
/// Controls are transparent with 1.5 pt ink outlines. No card chrome —
/// content sits on one flat paper bg, sections separate with ink-12% hairlines.
public enum AtlasTheme {

    /// Strong ink rule (header underlines, outlined controls). Controls keep this 1.5.
    public static let rule: CGFloat = 1.5

    /// Hairline separator width (1 pt) — sections/rows/cards. Controls use `rule` (1.5).
    public static let hairlineWidth: CGFloat = 1

    /// Wash — the tag/chip background tint for a given color (color at 13%).
    public static func wash(_ color: Color) -> Color { color.opacity(0.13) }

    public enum Colors {
        // One flat paper surface. Every level collapses to a single #f2efe6 —
        // no card/elevated tints; separation is 1px ink hairlines, never fills.
        public static let bgDeep      = Color(hex: "f2efe6")
        public static let bgBase      = Color(hex: "f2efe6")
        public static let bgSidebar   = Color(hex: "f2efe6")
        public static let bgCard      = Color(hex: "f2efe6") // card fills die — flat paper
        public static let bgElevated  = Color(hex: "f2efe6") // elevated fills die — flat paper

        public static let border       = Color(hex: "211d17").opacity(0.12)
        public static let borderStrong = Color(hex: "211d17").opacity(0.28)

        /// The editorial section separator (ink 12%).
        public static let hairline = Color(hex: "211d17").opacity(0.12)

        // Text
        public static let textPrimary   = Color(hex: "211d17")
        public static let textSecondary = Color(hex: "6f6a5e")
        public static let textMuted      = Color(hex: "9c968a")

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

/// THE shared tag/chip — tiny uppercase mono text on a color wash, no outline.
/// Used for course codes, statuses, space labels, etc. (adopted across views next wave).
public func atlasTag(text: String, color: Color) -> some View {
    Text(text)
        .atlasMono(size: 10, weight: .semibold)
        .textCase(.uppercase)
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            AtlasTheme.wash(color),
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
}

// MARK: - Reusable editorial view modifiers
//
// Ported from AtlasMobile with `atlas-` prefixed names (the mobile `ed-` names
// stay in AtlasMobile — declaring same-signature extensions in two visible
// modules would make mobile call sites ambiguous). Pure SwiftUI, no UIKit/AppKit:
// this package builds for both platforms.

private struct AtlasScaledFont: ViewModifier {
    @Environment(\.atlasTextScale) private var scale
    let size: CGFloat
    let weight: SwiftUI.Font.Weight
    let design: SwiftUI.Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// MONO type role (SF Mono) — every number, date, time, and uppercase section label.
    public func atlasMono(size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> some View {
        self.atlasFont(size: size, weight: weight, design: .monospaced)
    }

    /// Convenience mono for inline numerals — SF Mono at body size (13 / regular).
    public func atlasNumeric() -> some View {
        self.atlasMono(size: 13, weight: .regular)
    }

    /// SERIF type role (New York) — content titles.
    public func atlasTitleSerif(size: CGFloat) -> some View {
        self.atlasFont(size: size, weight: .semibold, design: .serif)
    }

    /// Big editorial screen title — 31 serif (New York), −0.03em tracking, ink.
    public func atlasScreenTitle() -> some View {
        self
            .atlasTitleSerif(size: 31)
            .tracking(-0.93)            // −0.03em × 31
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
    }

    /// Small uppercase caps label — 11 mono (SF Mono), wide tracking, secondary.
    public func atlasCapsLabel() -> some View {
        self
            .atlasMono(size: 11, weight: .bold)
            .tracking(2)                // wide mono tracking (~+0.18em × 11)
            .textCase(.uppercase)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
    }

    /// THE font entry point — every text style in the Mac app should render
    /// through this so it responds to the user's `atlasTextScale` setting.
    public func atlasFont(size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .rounded) -> some View {
        modifier(AtlasScaledFont(size: size, weight: weight, design: design))
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

    /// Hairline rule (ink 12%) along the bottom edge — the editorial row separator.
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
