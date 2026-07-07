import SwiftUI
import AtlasCore

/// Editorial segmented picker — transparent segments in a hairline-outlined
/// container; the active segment gets a 2px accent underline and semibold ink
/// text (never a fill). Options must be `Hashable & Identifiable`; pass a
/// label closure to extract display text.
struct AtlasSegmentedPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = selection == option
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            // Text-width and lifted off the frame edge — a full-width
                            // bar there collides with the container outline's corner
                            // curve on the first/last segment.
                            if selected {
                                Capsule()
                                    .fill(AtlasTheme.Colors.accent)
                                    .frame(height: 2)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
        )
    }
}
