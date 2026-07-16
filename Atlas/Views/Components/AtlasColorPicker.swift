import SwiftUI
import AtlasCore

/// Shared color chooser used by the space and project recolor popovers: a dense
/// grid of small swatches plus a `#RRGGBB` hex field for arbitrary colors. Emits
/// a `Color`; callers persist it (spaces store the Color, projects serialize it to
/// a token via `ColorToken.token(for:)` — hex round-trips as plain text).
struct AtlasColorGrid: View {
    /// The currently-applied color, ringed in the grid so the user sees their pick.
    var selected: Color?
    var onPick: (Color) -> Void

    @State private var hexDraft: String = ""

    /// A curated set of hues that read well on the cream paper background — the four
    /// theme colors plus a wheel of muted editorial tones. Small swatches, so many
    /// options fit without the popover growing tall.
    private static let palette: [String] = [
        "d97757", "c0503f", "e0655a", "b04f2f", "e08a3c", "febc2e", "d99a3c", "cbb34a",
        "6aa84f", "5fb98e", "4f9d7a", "8bbf5c", "3f8f6f", "4aa9a2", "5bb8c4", "3f9d9d",
        "5b9bd5", "4a7fc0", "6aa3e0", "3f6fa8", "7d7ad0", "b48ad9", "9b6fc9", "8a6fd0",
        "d97fb0", "c96f9d", "e08ab0", "a9805f", "8a6f52", "9b8d7a", "6d6558", "211d17",
    ]

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.palette, id: \.self) { hex in
                    let color = Color(hex: hex)
                    Button {
                        onPick(color)
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(AtlasTheme.Colors.textPrimary,
                                            lineWidth: isSelected(color) ? 2.5 : 0)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Text("#").atlasMono(size: 13).foregroundStyle(AtlasTheme.Colors.textMuted)
                TextField("RRGGBB", text: $hexDraft)
                    .textFieldStyle(.plain)
                    .atlasMono(size: 13)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .frame(width: 80)
                    .onSubmit(applyHex)
                Button(action: applyHex) {
                    Image(systemName: "arrow.right.circle.fill").atlasFont(size: 16)
                        .foregroundStyle(isValidHex ? AtlasTheme.Colors.accentText
                                                    : AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!isValidHex)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.border, lineWidth: AtlasTheme.hairlineWidth)
            )
        }
    }

    private func isSelected(_ color: Color) -> Bool {
        guard let selected else { return false }
        return color.atlasHexString == selected.atlasHexString
    }

    private var normalizedHex: String {
        hexDraft.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
    }

    private var isValidHex: Bool {
        let h = normalizedHex
        return h.count == 6 && h.allSatisfy { $0.isHexDigit }
    }

    private func applyHex() {
        guard isValidHex else { return }
        onPick(Color(hex: normalizedHex))
        hexDraft = ""
    }
}
