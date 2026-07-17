import SwiftUI
import AtlasCore

/// Space-level counterpart to InviteMemberSheet (Phase 2) — a single email
/// field + send button. Sharing a space shares everything inside it, so the
/// sheet spells out exactly what access that grants (see InviteAccessSummary).
struct InviteToSpaceSheet: View {
    let spaceId: UUID
    let spaceName: String
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invite to \u{201C}\(spaceName)\u{201D}")
                .atlasTitleSerif(size: 20)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)

            Rectangle()
                .fill(AtlasTheme.Colors.hairline)
                .frame(height: 1)

            InviteAccessSummary(canDo: [
                "See and edit every project in this space",
                "See and edit the tasks, events, and notes inside it",
                "Add, edit, and reschedule the space's calendar events"
            ])

            Rectangle()
                .fill(AtlasTheme.Colors.hairline)
                .frame(height: 1)

            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Spacer()
                Button { dismiss() } label: {
                    Text("Cancel")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .atlasOutlineControl()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await state.inviteToSpace(email: email, spaceId: spaceId)
                        sent = true
                    }
                } label: {
                    Text(sent ? "Sent" : "Send invite")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                        .atlasOutlineControl()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(email.isEmpty || sent)
                .opacity(email.isEmpty || sent ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
