import SwiftUI
import AtlasCore

/// Add-a-link sheet — the third reference flavor (`.link`): an external URL
/// (YouTube, article…) that attaches to a project's pool with just a title + URL.
/// Editorial idiom, mirrors `NewProjectSheet`. Creates the reference via
/// `AppState.addLink` (which lands it `.synced` — a link has nothing to sync).
struct AddLinkSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var title: String = ""
    @State private var urlString: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().overlay(AtlasTheme.Colors.hairline)
            formBody
        }
        .frame(width: 420, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Add link")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)

            Button("Add") { save() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(canSave ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            fieldGroup(label: "TITLE") {
                boxedField {
                    TextField("What is this?", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }

            fieldGroup(label: "URL") {
                boxedField {
                    TextField("https://…", text: $urlString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .onSubmit { save() }
                }
            }
        }
        .padding(24)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).atlasCapsLabel()
            content()
        }
    }

    @ViewBuilder
    private func boxedField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1)
            )
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Normalizes the pasted URL — prepends `https://` when the user omits a scheme
    /// so a bare `youtube.com/…` still opens. `nil` if it can't form a valid URL.
    private var normalizedURL: URL? {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private var canSave: Bool { !trimmedTitle.isEmpty && normalizedURL != nil }

    private func save() {
        guard !trimmedTitle.isEmpty, let url = normalizedURL else { return }
        state.addLink(title: trimmedTitle, url: url.absoluteString, projectID: projectID)
        dismiss()
    }
}
