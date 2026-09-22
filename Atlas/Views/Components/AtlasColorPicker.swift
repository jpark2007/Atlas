import SwiftUI
import AtlasCore

/// The app's one color chooser — every color pick (space, new space, project, class,
/// new class, Apple calendar; Mac and iOS) uses it: the `AtlasTheme.Colors.palette`
/// swatches plus a `#RRGGBB` hex field for arbitrary colors. Emits a `Color`; callers
/// persist it via `ColorToken.token(for:)` (named tokens stay names, others hex).
struct AtlasColorGrid: View {
    /// The currently-applied color, ringed in the grid so the user sees their pick.
    var selected: Color?
    var onPick: (Color) -> Void

    @State private var hexDraft: String = ""

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AtlasTheme.Colors.palette.indices, id: \.self) { i in
                    let color = AtlasTheme.Colors.palette[i]
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
                .help("Apply this hex color")
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
