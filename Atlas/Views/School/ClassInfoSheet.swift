import SwiftUI
import AtlasCore

/// The syllabus "Class info" card, in full — and the one place it can be edited by hand.
///
/// The card on the class page shows the gist; a policy is the kind of thing you are held
/// to word for word ("more than four missed classes and you fail"), so clicking it opens
/// this. Editing lives here too: before this, the only way to move office hours was to
/// rescan the whole syllabus, which replaced everything.
///
/// Both modes are laid out as the same page in two states — the ruled section headers,
/// the weight chips and the numbered policy rows are the class page's grading/policies
/// cards at full size, so reading and editing never look like two different screens.
struct ClassInfoSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    /// Opens straight into the fields — the "Edit" affordance on the card.
    var startEditing = false

    @State private var editing = false
    @State private var officeHours = ""
    @State private var policies: [Line] = []
    @State private var weights: [WeightLine] = []
    @State private var didLoad = false

    /// One editable bullet. Identified by its own id, not its text, so two identical
    /// lines don't collapse into one row while you're typing.
    private struct Line: Identifiable {
        let id = UUID()
        var text: String
    }

    /// A weight, edited as the two things it actually is: what it's for, and what share
    /// of the grade it carries. `original` is the syllabus's own sentence — a row you
    /// never touch is written back exactly as it arrived rather than reformatted.
    private struct WeightLine: Identifiable {
        let id = UUID()
        var label: String
        var percent: String
        var original: String?

        init(original: String) {
            let parts = ClassInfoFormat.weight(original)
            label = parts.label
            percent = parts.percent ?? ""
            self.original = original
        }

        init() { label = ""; percent = ""; original = nil }

        /// The stored string. Unchanged rows keep their wording; an edited one is
        /// composed in the shape the card reads back cleanly.
        var stored: String {
            let label = self.label.trimmingCharacters(in: .whitespaces)
            let percent = self.percent.trimmingCharacters(in: .whitespaces)
            if let original, ClassInfoFormat.weight(original).label == label,
               (ClassInfoFormat.weight(original).percent ?? "") == percent {
                return original
            }
            guard !percent.isEmpty else { return label }
            let suffixed = percent.hasSuffix("%") ? percent : percent + "%"
            return label.isEmpty ? suffixed : "\(label) — \(suffixed)"
        }
    }

    private var info: ClassInfoCard { project.classInfo ?? ClassInfoCard() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if editing { editor } else { reader }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 540, height: 580, alignment: .topLeading)
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

    /// The class page's `infoColumnHeader`, at sheet size: a name, the number that
    /// summarises the section, and the ink rule under both.
    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing)
                        .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            .padding(.bottom, 8)
            Rectangle()
                .fill(AtlasTheme.Colors.textPrimary)
                .frame(height: AtlasTheme.rule)
        }
    }

    // MARK: - Read

    @ViewBuilder
    private var reader: some View {
        // The syllabus's own "Total: 100%" row is dropped here for the same reason the
        // card drops it: the header computes the total, so keeping it double-counts.
        let weightRows = ClassInfoFormat.weightRows(info.gradeWeights)

        if SyllabusDraft.isEmpty(info) {
            Text("Nothing here yet. Scan a syllabus, or write it in yourself.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !weightRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Grading", trailing: ClassInfoFormat.weightTotal(weightRows))
                VStack(spacing: 6) {
                    ForEach(Array(weightRows.enumerated()), id: \.offset) { _, line in
                        weightChip(ClassInfoFormat.weight(line))
                    }
                }
                .padding(.top, 10)
            }
        }
        if !info.policies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Policies", trailing: "\(info.policies.count)")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(info.policies.enumerated()), id: \.offset) { index, line in
                        policyRow(index: index, parts: ClassInfoFormat.policy(line))
                        if index < info.policies.count - 1 {
                            Rectangle()
                                .fill(AtlasTheme.Colors.hairline)
                                .frame(height: AtlasTheme.hairlineWidth)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        if let hours = info.officeHours, !hours.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Office hours", trailing: nil)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock").atlasFont(size: 11)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Text(hours)
                        .atlasFont(size: 13, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }
        }
    }

    /// Label left, percent right — the card's weight row, allowed to wrap here.
    private func weightChip(_ parts: (label: String, percent: String?)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(parts.label)
                .atlasFont(size: 12.5, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let percent = parts.percent {
                Text(percent)
                    .atlasFont(size: 13, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: AtlasTheme.hairlineWidth)
        )
    }

    /// One policy, in full. Numbered so a long list stays countable, lead-in bold above
    /// the wording — no line limit anywhere, since the wording is the whole point.
    private func policyRow(index: Int, parts: (title: String?, body: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .atlasMono(size: 10.5, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                if let title = parts.title {
                    Text(title)
                        .atlasFont(size: 13, weight: .bold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(parts.body)
                    .atlasFont(size: 13, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    // MARK: - Edit

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The same total the card shows, live while you type — a set of weights
            // that no longer adds up is visible as you make it so.
            sectionHeader("Grading", trailing: ClassInfoFormat.weightTotal(weights.map(\.stored)))
            VStack(spacing: 6) {
                ForEach($weights) { $weight in
                    HStack(spacing: 8) {
                        TextField("Midterm", text: $weight.label)
                            .textFieldStyle(.plain)
                            .atlasFont(size: 13, design: .rounded)
                        TextField("25%", text: $weight.percent)
                            .textFieldStyle(.plain)
                            .atlasFont(size: 13, weight: .semibold, design: .rounded)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        removeButton { weights.removeAll { $0.id == weight.id } }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: AtlasTheme.hairlineWidth)
                    )
                }
            }
            .padding(.top, 10)
            addButton("Another weight") { weights.append(WeightLine()) }
        }

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Policies", trailing: policies.isEmpty ? nil : "\(policies.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach($policies) { $policy in
                    let number = (policies.firstIndex { $0.id == policy.id } ?? 0) + 1
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", number))
                            .atlasMono(size: 10.5, weight: .semibold)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .padding(.top, 8)
                        TextField("Late work — homework closes at 11:59pm",
                                  text: $policy.text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...6)
                            .atlasFont(size: 13, design: .rounded)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                        removeButton { policies.removeAll { $0.id == policy.id } }
                            .padding(.top, 8)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
            addButton("Another policy") { policies.append(Line(text: "")) }
        }

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Office hours", trailing: nil)
            TextField("Tue & Thu 2–4pm, Tech Hall 310", text: $officeHours, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .atlasFont(size: 13, design: .rounded)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                .padding(.top, 10)
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").atlasFont(size: 10, weight: .semibold)
                Text(title).atlasFont(size: 12, weight: .semibold, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }

    // MARK: - Load / save

    private func load(force: Bool = false) {
        guard force || !didLoad else { return }
        didLoad = true
        officeHours = info.officeHours ?? ""
        weights = info.gradeWeights.map { WeightLine(original: $0) }
        policies = info.policies.map { Line(text: $0) }
        if !force { editing = startEditing }
    }

    private func save() {
        let hours = officeHours.trimmingCharacters(in: .whitespacesAndNewlines)
        // Blank rows are how you delete one — nobody should have to hunt for a minus.
        let card = ClassInfoCard(gradeWeights: cleanedWeights(),
                                 policies: cleaned(policies),
                                 officeHours: hours.isEmpty ? nil : hours)
        state.setClassInfo(projectID: project.id, info: SyllabusDraft.isEmpty(card) ? nil : card)
        dismiss()
    }

    private func cleanedWeights() -> [String] {
        weights.map { $0.stored.trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
    }

    private func cleaned(_ lines: [Line]) -> [String] {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
    }
}
