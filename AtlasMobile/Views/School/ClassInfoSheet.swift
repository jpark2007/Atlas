import SwiftUI
import AtlasCore

/// The syllabus "Class info" card, in full — and the one place it can be edited by hand.
///
/// The class page shows the gist; a policy is the kind of thing you are held to word for
/// word ("more than four missed classes and you fail"), so tapping the card opens this.
/// Editing lives here too: before this, moving office hours meant rescanning the whole
/// syllabus, which replaced everything.
struct ClassInfoSheet: View {
    @EnvironmentObject private var store: MobileStore
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if editing { editor } else { reader }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 60)
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
        .padding(.bottom, 24)
    }

    // MARK: - Read

    @ViewBuilder
    private var reader: some View {
        if SyllabusDraft.isEmpty(info) {
            Text("Nothing here yet. Scan a syllabus, or write it in yourself.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let hours = info.officeHours, !hours.isEmpty {
            readGroup("Office hours", [hours])
        }
        if !info.gradeWeights.isEmpty {
            readGroup("How it's graded", info.gradeWeights)
        }
        if !info.policies.isEmpty {
            readGroup("Policies", info.policies)
        }
    }

    private func readGroup(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).edCapsLabel()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("·").font(.system(size: 14))
                    // No line limit — the whole point of this screen is the full wording.
                    Text(line)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(MobileTheme.muted)
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: - Edit

    private var editor: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Office hours").edCapsLabel()
                field("Tue & Thu 2–4pm, Tech Hall 310", text: $officeHours)
            }
            lineEditor("How it's graded", placeholder: "Midterm — 25%",
                       lines: $weights, addLabel: "Another weight")
            lineEditor("Policies", placeholder: "More than 4 missed classes = fail",
                       lines: $policies, addLabel: "Another policy")
            Button { save() } label: {
                Text("Save")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
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

    private func lineEditor(_ title: String, placeholder: String,
                            lines: Binding<[Line]>, addLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).edCapsLabel()
            ForEach(lines) { $line in
                HStack(spacing: 10) {
                    field(placeholder, text: $line.text)
                    Button { lines.wrappedValue.removeAll { $0.id == line.id } } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(MobileTheme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { lines.wrappedValue.append(Line(text: "")) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text(addLabel).font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(MobileTheme.faint)
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
        store.setClassInfo(projectID: project.id, info: SyllabusDraft.isEmpty(card) ? nil : card)
        MobileTheme.Haptic.success()
        dismiss()
    }

    private func cleaned(_ lines: [Line]) -> [String] {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
    }
}
