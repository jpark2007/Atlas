import SwiftUI
import AtlasCore

/// A single email field + send button. No autocomplete, no friends list —
/// per the design spec, email invite is the entire v1 invitation mechanism.
struct InviteMemberSheet: View {
    let projectId: UUID
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite to project")
                .atlasFont(size: 17, weight: .semibold)

            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(sent ? "Sent" : "Send Invite") {
                    Task {
                        await state.invite(email: email, toProject: projectId)
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
