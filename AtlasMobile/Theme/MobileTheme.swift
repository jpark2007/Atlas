import SwiftUI
import AtlasCore
import UIKit

/// Editorial Minimal · LIGHT · clay — the iOS design system.
///
/// Tokens are the source of truth (mirrors `docs/experiments/ui-style-directions-v2.html`
/// style 4). RULES: accent = live/NOW/brand ONLY, never a button fill. Controls are
/// transparent with 1.5 pt ink outlines. No card chrome — content sits on the bg,
/// separated by rules. Type is SF Pro Rounded everywhere.
enum MobileTheme {

    // MARK: Colors  (Color(hex:) comes from AtlasCore)
    static let bg      = Color(hex: "fbfaf7")
    static let ink     = Color(hex: "1a191d")
    static let muted   = Color(hex: "6c6a72")
    static let faint   = Color(hex: "9a98a0")
    static let hairline = Color.black.opacity(0.08)
    /// Clay accent — graphics only (NOW / live / brand). Never a fill.
    static let accent     = Color(hex: "d97757")
    /// Darkened accent for TEXT on light surfaces (AA).
    static let accentText = Color(hex: "b04f2f")

    // MARK: Radii (continuous corners)
    static let radiusCard: CGFloat    = 24
    static let radiusControl: CGFloat = 19
    static let radiusChip: CGFloat    = 13

    /// Strong ink rule (header underlines, outlined controls).
    static let rule: CGFloat = 1.5

    // MARK: Motion — ONE vocabulary, used everywhere (spec §5)
    /// Standard spring — "satisfying but quiet". Every state change animates with this.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Hero spring — livelier. CAPTURE ONLY: the app's one expressive moment.
    static let heroSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)

    /// The haptic map: tap = check-off and light actions, success = capture commit,
    /// selection = toggles/filters. Views use these — never their own generators.
    enum Haptic {
        static func tap()       { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    }
}

// MARK: - Reusable view modifiers

extension View {
    /// Big editorial screen title — 31 / heavy, −0.03em tracking, ink.
    func edScreenTitle() -> some View {
        self
            .font(.system(size: 31, weight: .heavy, design: .rounded))
            .tracking(-0.93)            // −0.03em × 31
            .foregroundStyle(MobileTheme.ink)
    }

    /// Small uppercase caps label — 11 / bold, +0.08em tracking, muted.
    func edCapsLabel() -> some View {
        self
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.88)             // +0.08em × 11
            .textCase(.uppercase)
            .foregroundStyle(MobileTheme.muted)
    }

    /// Transparent control with a 1.5 pt ink outline, control radius (19).
    func edOutlineControl() -> some View {
        self
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .overlay(
                RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                    .strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule)
            )
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous))
    }

    /// Hairline rule (black 8%) along the bottom edge — the editorial row separator.
    func edHairlineBelow() -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(MobileTheme.hairline)
                .frame(height: 1)
        }
    }
}
