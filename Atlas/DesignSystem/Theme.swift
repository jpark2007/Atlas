import SwiftUI

/// Atlas design tokens — extracted from the approved dark prototype.
enum AtlasTheme {
    enum Colors {
        // Warm near-black backgrounds (deepest → most elevated)
        static let bgDeep      = Color(hex: "100e0c")
        static let bgBase      = Color(hex: "16130f")
        static let bgSidebar   = Color(hex: "1a140f")
        static let bgCard      = Color(hex: "1c1814")
        static let bgElevated  = Color(hex: "211d18")

        static let border      = Color.white.opacity(0.06)
        static let borderStrong = Color.white.opacity(0.10)

        // Text
        static let textPrimary   = Color(hex: "f3ede4")
        static let textSecondary = Color(hex: "a89b8a")
        static let textMuted     = Color(hex: "6f655a")

        // Brand accent
        static let accent     = Color(hex: "ff8c42")
        static let accentDeep = Color(hex: "ff6b1a")

        // Semantic status tokens
        static let warning  = Color(hex: "febc2e") // warm amber
        static let danger   = Color(hex: "ff5c5c") // warm red

        // Space identity colors
        static let school   = Color(hex: "5b9bd5")
        static let personal = Color(hex: "5fb98e")
        static let side     = Color(hex: "b48ad9")
        static let yellow   = Color(hex: "febc2e")
        static let green    = Color(hex: "5fb98e")
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let card: CGFloat = 14
    }

    enum Font {
        static func kicker() -> SwiftUI.Font { .system(size: 11, weight: .semibold) }
        static func sectionLabel() -> SwiftUI.Font { .system(size: 11, weight: .semibold) }
        static func greeting() -> SwiftUI.Font { .system(size: 28, weight: .semibold) }
        static func cardTitle() -> SwiftUI.Font { .system(size: 14, weight: .semibold) }
        static func body() -> SwiftUI.Font { .system(size: 13, weight: .regular) }
        static func bodyMedium() -> SwiftUI.Font { .system(size: 13, weight: .medium) }
        static func small() -> SwiftUI.Font { .system(size: 11, weight: .regular) }
    }
}

/// Dark-themed segmented picker that replaces the macOS default grey segmented control.
/// Options must be `Hashable & Identifiable`. Pass a label closure to extract display text.
struct AtlasSegmentedPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            selection == option
                                ? AtlasTheme.Colors.bgDeep
                                : AtlasTheme.Colors.textSecondary
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == option ? AtlasTheme.Colors.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AtlasTheme.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

/// A standard Atlas content card.
struct AtlasCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
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
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
