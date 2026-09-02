import SwiftUI
import AtlasCore

/// The syllabus "Class info" card, in full — and the one place it can be edited by hand.
///
/// The class page shows the gist; a policy is the kind of thing you are held to word for
/// word ("more than four missed classes and you fail"), so tapping the card opens this.
/// Editing lives here too: before this, moving office hours meant rescanning the whole
/// syllabus, which replaced everything.
///
/// Both modes are the same page in two states — the ruled section headers, the weight
/// rows and the numbered policies are the class page's grading/policies cards at full
/// size, so reading and editing never look like two different screens.
struct ClassInfoSheet: View {
    @EnvironmentObject private var store: MobileStore
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
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if editing { editor } else { reader }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Class info").edScreenTitle()
                Text(editing ? "Your words or the syllabus's — Atlas never scores anything here."
                             : "What \(project.name)'s syllabus says, in full.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if editing {
                Button { load(force: true); editing = false } label: {
                    Text("Cancel").edCapsLabel()
                }
                .buttonStyle(.plain)
            } else {
                Button { editing = true } label: {
                    Text("Edit")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.accentText)
                }
                .buttonStyle(.plain)
                Button { dismiss() } label: {
                    Text("Done").edCapsLabel()
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
            }
        }
    }

    /// The class page's `infoColumnHeader`, at sheet size: a name, the number that
    /// summarises the section, and the ink rule under both.
    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.faint)
                }
            }
            .padding(.bottom, 8)
            Rectangle().fill(MobileTheme.ink).frame(height: MobileTheme.rule)
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !weightRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Grading", trailing: ClassInfoFormat.weightTotal(weightRows))
                VStack(spacing: 7) {
                    ForEach(Array(weightRows.enumerated()), id: \.offset) { _, line in
                        weightRow(ClassInfoFormat.weight(line))
                    }
                }
                .padding(.top, 12)
            }
        }
        if !info.policies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Policies", trailing: "\(info.policies.count)")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(info.policies.enumerated()), id: \.offset) { index, line in
                        policyRow(index: index, parts: ClassInfoFormat.policy(line))
                        if index < info.policies.count - 1 {
                            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        if let hours = info.officeHours, !hours.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Office hours", trailing: nil)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MobileTheme.faint)
                    Text(hours)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
        }
    }

    /// Label left, percent right — the class page's weight row, allowed to wrap here.
    private func weightRow(_ parts: (label: String, percent: String?)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(parts.label)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let percent = parts.percent {
                Text(percent)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .strokeBorder(MobileTheme.hairline, lineWidth: 1))
    }

    /// One policy, in full. Numbered so a long list stays countable, lead-in bold above
    /// the wording — no line limit anywhere, since the wording is the whole point.
    private func policyRow(index: Int, parts: (title: String?, body: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.faint)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                if let title = parts.title {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(parts.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    // MARK: - Edit

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The same total the card shows, live while you type — a set of weights
            // that no longer adds up is visible as you make it so.
            sectionHeader("Grading", trailing: ClassInfoFormat.weightTotal(weights.map(\.stored)))
            VStack(spacing: 8) {
                ForEach($weights) { $weight in
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            TextField("Midterm", text: $weight.label)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(MobileTheme.ink)
                                .tint(MobileTheme.accent)
                            TextField("25%", text: $weight.percent)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(MobileTheme.ink)
                                .tint(MobileTheme.accent)
                                .keyboardType(.numbersAndPunctuation)
                                .frame(width: 62)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                            .strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
                        removeButton { weights.removeAll { $0.id == weight.id } }
                    }
                }
            }
            .padding(.top, 12)
            addButton("Another weight") { weights.append(WeightLine()) }
        }

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Policies", trailing: policies.isEmpty ? nil : "\(policies.count)")
            VStack(alignment: .leading, spacing: 10) {
                ForEach($policies) { $policy in
                    let number = (policies.firstIndex { $0.id == policy.id } ?? 0) + 1
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", number))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.faint)
                            .padding(.top, 12)
                        field("Late work — homework closes at 11:59pm", text: $policy.text)
                        removeButton { policies.removeAll { $0.id == policy.id } }
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.top, 12)
            addButton("Another policy") { policies.append(Line(text: "")) }
        }

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Office hours", trailing: nil)
            field("Tue & Thu 2–4pm, Tech Hall 310", text: $officeHours)
                .padding(.top, 12)
        }

        Button { save() } label: {
            Text("Save")
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity)
                .edOutlineControl()
        }
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(MobileTheme.faint)
        }
        .buttonStyle(.plain)
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(MobileTheme.faint)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
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
        store.setClassInfo(projectID: project.id, info: SyllabusDraft.isEmpty(card) ? nil : card)
        MobileTheme.Haptic.success()
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
