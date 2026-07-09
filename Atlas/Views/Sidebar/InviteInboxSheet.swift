import SwiftUI
import AtlasCore

/// One row per pending invite, accept/decline inline. Deliberately plain —
/// this is a low-frequency utility sheet, not a feature surface.
struct InviteInboxSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Invitations")
                .atlasFont(size: 17, weight: .semibold)
                .padding(16)

            if state.pendingInvites.isEmpty {
                Text("No pending invitations.")
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(16)
            }

            ForEach(state.pendingInvites, id: \.id) { invite in
                HStack {
                    Text(invite.kind == .space ? "Space invite" : "Project invite")
                        .atlasFont(size: 14)
                    Spacer()
                    Button("Decline") {
                        Task { await state.respondToInvite(invite, accept: false) }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Button("Accept") {
                        Task { await state.respondToInvite(invite, accept: true) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
            }

            Spacer(minLength: 8)
        }
        .frame(width: 340, height: 240)
    }
}
