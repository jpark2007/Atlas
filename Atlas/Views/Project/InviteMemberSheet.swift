import SwiftUI
import AtlasCore

/// A single email field + send button. No autocomplete, no friends list —
/// per the design spec, email invite is the entire v1 invitation mechanism.
/// The sheet spells out what sharing a project grants (see InviteAccessSummary).
struct InviteMemberSheet: View {
    let projectId: UUID
    let projectName: String
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invite to \u{201C}\(projectName)\u{201D}")
                .atlasTitleSerif(size: 20)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)

            Rectangle()
                .fill(AtlasTheme.Colors.hairline)
                .frame(height: 1)

            InviteAccessSummary(canDo: [
                "See and edit this project",
                "See and edit its tasks, events, and notes",
                "Add, edit, and reschedule its calendar events"
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
                        await state.invite(email: email, toProject: projectId)
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
