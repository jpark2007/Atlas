import SwiftUI
import AtlasCore

/// The syllabus "Class info" card, in full — and the one place it can be edited by hand.
///
/// The card on the class page shows the gist; a policy is the kind of thing you are held
/// to word for word ("more than four missed classes and you fail"), so clicking it opens
/// this. Editing lives here too: before this, the only way to move office hours was to
/// rescan the whole syllabus, which replaced everything.
struct ClassInfoSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    /// Opens straight into the fields — the "Edit" affordance on the card.
    var startEditing = false

    @State private var editing = false
    @State private var officeHours = ""
    @State private var policies: [Line] = []
    @State private var weights: [Line] = []
    @State private var didLoad = false

    /// One editable bullet. Identified by its own id, not its text, so two identical
    /// lines don't collapse into one row while you're typing.
    private struct Line: Identifiable {
        let id = UUID()
        var text: String
    }

    private var info: ClassInfoCard { project.classInfo ?? ClassInfoCard() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if editing { editor } else { reader }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 540, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(editing ? "Your words or the syllabus's — Atlas never scores anything here."
                             : "What the syllabus says, in full.")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
            if editing {
                Button("Cancel") { load(force: true); editing = false }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Edit") { editing = true }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    // MARK: - Read

    @ViewBuilder
    private var reader: some View {
        if info.gradeWeights.isEmpty && info.policies.isEmpty && (info.officeHours?.isEmpty ?? true) {
            Text("Nothing here yet. Scan a syllabus, or write it in yourself.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        if let hours = info.officeHours, !hours.isEmpty {
            readGroup("OFFICE HOURS", [hours])
        }
        if !info.gradeWeights.isEmpty {
            readGroup("HOW IT'S GRADED", info.gradeWeights)
        }
        if !info.policies.isEmpty {
            readGroup("POLICIES", info.policies)
        }
    }

    private func readGroup(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).atlasCapsLabel()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7) {
                    Text("·").atlasFont(size: 13)
                    // No line limit — the whole point of this screen is the full wording.
                    Text(line)
                        .atlasFont(size: 13, design: .rounded)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Edit

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("OFFICE HOURS").atlasCapsLabel()
                TextField("Tue & Thu 2–4pm, Tech Hall 310", text: $officeHours, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .atlasFont(size: 13, design: .rounded)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            }
            lineEditor("HOW IT'S GRADED", placeholder: "Midterm — 25%", lines: $weights,
                       addLabel: "Another weight")
            lineEditor("POLICIES", placeholder: "More than 4 missed classes = fail",
                       lines: $policies, addLabel: "Another policy")
        }
    }

    private func lineEditor(_ title: String, placeholder: String,
                            lines: Binding<[Line]>, addLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).atlasCapsLabel()
            ForEach(lines) { $line in
                HStack(spacing: 8) {
                    TextField(placeholder, text: $line.text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .atlasFont(size: 13, design: .rounded)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                    Button { lines.wrappedValue.removeAll { $0.id == line.id } } label: {
                        Image(systemName: "minus.circle")
                            .atlasFont(size: 12)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { lines.wrappedValue.append(Line(text: "")) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").atlasFont(size: 10, weight: .semibold)
                    Text(addLabel).atlasFont(size: 12, weight: .semibold, design: .rounded)
                }
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / save

    private func load(force: Bool = false) {
        guard force || !didLoad else { return }
        didLoad = true
        officeHours = info.officeHours ?? ""
        weights = info.gradeWeights.map { Line(text: $0) }
        policies = info.policies.map { Line(text: $0) }
        if !force { editing = startEditing }
    }

    private func save() {
        let hours = officeHours.trimmingCharacters(in: .whitespacesAndNewlines)
        // Blank rows are how you delete one — nobody should have to hunt for a minus.
        let card = ClassInfoCard(gradeWeights: cleaned(weights),
                                 policies: cleaned(policies),
                                 officeHours: hours.isEmpty ? nil : hours)
        state.setClassInfo(projectID: project.id, info: SyllabusDraft.isEmpty(card) ? nil : card)
        dismiss()
    }

    private func cleaned(_ lines: [Line]) -> [String] {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
    }
}
