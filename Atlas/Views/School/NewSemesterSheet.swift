import SwiftUI
import AtlasCore

/// "Start a new semester" — creates the next term and offers to carry the structure
/// forward. Copy-forward recreates class SHELLS (name / code / color) only: last
/// semester's assignments are not next semester's.
///
/// Putting the previous term's classes away is offered here too, because that's when a
/// student actually thinks about it. It's a soft archive — nothing is deleted, ever.
struct NewSemesterSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// The term being succeeded, if any — the source for copy-forward.
    let previous: Term?

    @State private var name = ""
    @State private var startsOn = Date()
    @State private var endsOn = Date()
    @State private var copyForward = true
    @State private var archivePrevious = true
    @State private var didLoad = false

    private var previousClasses: [Project] {
        guard let previous else { return [] }
        return state.classes(in: previous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("NEW SEMESTER").atlasCapsLabel()
                    TextField("Spring 2027", text: $name)
                        .textFieldStyle(.plain)
                        .atlasFont(size: 15, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                    HStack(spacing: 14) {
                        DatePicker("First day", selection: $startsOn, displayedComponents: .date)
                        DatePicker("Last day", selection: $endsOn, displayedComponents: .date)
                    }
                    .datePickerStyle(.compact)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                }

                if !previousClasses.isEmpty, let previous {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $copyForward) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Take my classes with me")
                                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                Text("Recreates \(previousClasses.count) empty \(previousClasses.count == 1 ? "class" : "classes") — same names and colors, no old work.")
                                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                            }
                        }
                        Toggle(isOn: $archivePrevious) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Put \(previous.name) away")
                                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                Text("Out of the sidebar, still searchable. Nothing is deleted.")
                                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
                }

                Text("You can add dates, breaks and holidays from the semester menu once it exists.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(24)
        }
        .frame(width: 460, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Start a new semester")
                .atlasFont(size: 19, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
            Button("Create") { create() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(trimmed.isEmpty ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.accentText)
                .disabled(trimmed.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = previous.map { SchoolCalendar.nextTermName(after: $0.name) } ?? ""
        // Start the day after the last term ended when we know it, else today.
        let base = previous?.endsOn.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) } ?? Date()
        startsOn = base
        endsOn = Calendar.current.date(byAdding: .month, value: 4, to: base) ?? base
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        let term = Term(name: trimmed, startsOn: startsOn, endsOn: endsOn)
        state.saveTerm(term)
        if let previous, copyForward { state.copyClassesForward(from: previous, to: term) }
        if let previous, archivePrevious { state.archiveClasses(in: previous) }
        state.schoolTermOverride = nil
        dismiss()
    }
}
