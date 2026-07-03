import SwiftUI
import AtlasCore

/// Create-a-Space form (follow-up: add a top-level bucket). Presented from the
/// sidebar's "+ Space" affordance under the SPACES header. On Create the new
/// space is appended via `AppState.addSpace`, then expanded in the sidebar.
struct NewSpaceSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var colorToken: String = "side"

    /// The palette the user can pick from — the four AtlasTheme space tokens.
    /// Token strings match `ColorToken` so persistence round-trips cleanly.
    private let palette: [(token: String, label: String, color: Color)] = [
        ("school",   "Blue",   AtlasTheme.Colors.school),
        ("personal", "Green",  AtlasTheme.Colors.personal),
        ("side",     "Purple", AtlasTheme.Colors.side),
        ("accent",   "Orange", AtlasTheme.Colors.accent),
    ]

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
            VStack(alignment: .leading, spacing: 2) {
                Text("New Space")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text("A new top-level bucket alongside your other spaces.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)

            Button("Create") { save() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(trimmedName.isEmpty ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.accentText)
                .disabled(trimmedName.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 22) {

            fieldGroup(label: "NAME") {
                boxedField {
                    TextField("Space name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .onSubmit(save)
                }
            }

            fieldGroup(label: "COLOR") {
                HStack(spacing: 12) {
                    ForEach(palette, id: \.token) { swatch in
                        Button {
                            colorToken = swatch.token
                        } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(AtlasTheme.Colors.textPrimary,
                                                lineWidth: colorToken == swatch.token ? 2.5 : 0)
                                        .padding(-3)
                                )
                                .help(swatch.label)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(24)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .atlasCapsLabel()
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedColor: Color {
        ColorToken.color(for: colorToken)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let created = state.addSpace(name: trimmedName, color: selectedColor) {
            state.expandedSpaces.insert(created.id)
        }
        dismiss()
    }
}
