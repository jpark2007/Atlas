import SwiftUI
import AtlasCore

/// Lightweight identifier so the sidebar can drive `.sheet(item:)` with the
/// space the user tapped "+" on.
struct NewProjectTarget: Identifiable {
    let id = UUID()
    let spaceName: String
}

/// Create-a-Project form (WS-8). Presented from the sidebar's per-space "+".
/// `spaceName` is fixed to the space the user invoked it from; on Create the new
/// project is appended to that space, the space is expanded, and the detail pane
/// navigates to it.
struct NewProjectSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let spaceName: String

    @State private var name: String = ""
    @State private var code: String = ""
    @State private var isClass: Bool = false
    @State private var overview: String = ""

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
                Text("New Project")
                    .atlasFont(size: 19, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.calendarSpaceColor(named: spaceName))
                        .frame(width: 7, height: 7)
                    Text(spaceName)
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)

            Button("Create") { save() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                fieldGroup(label: "NAME") {
                    boxedField {
                        TextField("Project or class name", text: $name)
                            .textFieldStyle(.plain)
                            .atlasFont(size: 15, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }

                fieldGroup(label: "CODE (OPTIONAL)") {
                    boxedField {
                        TextField("e.g. CS 201", text: $code)
                            .textFieldStyle(.plain)
                            .atlasFont(size: 15, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }

                Toggle(isOn: $isClass) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This is a class")
                            .atlasFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Classes show a dotted marker and class badge.")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(AtlasTheme.Colors.textPrimary)

                fieldGroup(label: "OVERVIEW (OPTIONAL)") {
                    ZStack(alignment: .topLeading) {
                        if overview.isEmpty {
                            Text("What is this project about?")
                                .atlasFont(size: 14, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $overview)
                            .atlasFont(size: 14, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minHeight: 80)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                    )
                }
            }
            .padding(24)
        }
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

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let created = state.addProject(
            toSpaceNamed: spaceName,
            name: trimmedName,
            code: code,
            isClass: isClass,
            overview: overview.trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            if let spaceID = state.spaces.first(where: { $0.name == spaceName })?.id {
                state.expandedSpaces.insert(spaceID)
            }
            state.route = .project(created.id)
        }
        dismiss()
    }
}
