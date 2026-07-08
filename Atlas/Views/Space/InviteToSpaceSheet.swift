import SwiftUI
import AtlasCore

/// Space-level counterpart to InviteMemberSheet (Phase 2) — a single email
/// field + send button. Sharing a space shares everything inside it.
struct InviteToSpaceSheet: View {
    let spaceId: UUID
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite to space")
                .atlasFont(size: 17, weight: .semibold)

            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(sent ? "Sent" : "Send Invite") {
                    Task {
                        await state.inviteToSpace(email: email, spaceId: spaceId)
                        sent = true
                    }
                }
                .disabled(email.isEmpty || sent)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
