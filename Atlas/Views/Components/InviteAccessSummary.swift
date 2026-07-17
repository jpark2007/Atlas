import SwiftUI
import AtlasCore

/// The access disclosure shared by both invite sheets — tells the person doing
/// the inviting exactly what the invitee will (and won't) be able to see. The
/// "able to" lines are scope-specific (space vs. project); the "stays private"
/// lines are identical everywhere, so they live here.
struct InviteAccessSummary: View {
    /// The three "they'll be able to" lines, scoped to a space or a project.
    let canDo: [String]

    private let staysPrivate = [
        "Your personal Apple and Google calendars",
        "Your other spaces and projects"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("THEY'LL BE ABLE TO").atlasCapsLabel()
                ForEach(canDo, id: \.self) { row in
                    accessRow(row) {
                        Image(systemName: "checkmark")
                            .atlasFont(size: 10, weight: .bold)
                            .foregroundStyle(AtlasTheme.Colors.accentText)
                            .frame(width: 12)
                    }
                }
            }

            Rectangle()
                .fill(AtlasTheme.Colors.hairline)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("STAYS PRIVATE").atlasCapsLabel()
                ForEach(staysPrivate, id: \.self) { row in
                    accessRow(row) {
                        Circle()
                            .fill(AtlasTheme.Colors.textMuted)
                            .frame(width: 4, height: 4)
                            .frame(width: 12)
                    }
                }
            }
        }
    }

    private func accessRow<Glyph: View>(_ text: String, @ViewBuilder glyph: () -> Glyph) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            glyph()
            Text(text)
                .atlasFont(size: 13, weight: .regular, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
