import SwiftUI
import AtlasCore

/// Name a term, date it, and list its Key Dates. Used by the semester wizard, the
/// "start a new semester" flow, and the one-time "date your term" migration prompt.
///
/// Key Dates are the cheap differentiator: competitors make students type classes-begin,
/// add/drop and every break by hand somewhere they'll never look again. Here they land on
/// the term and the calendar flags them — and holidays/breaks additionally stop class
/// meetings from being drawn (see `SchoolCalendar.isBreakDay`).
struct TermEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// The term being edited — a brand-new one when it isn't in `state.terms` yet.
    let term: Term
    /// True for the migration prompt: saving also files every undated class into this term.
    var adoptUndatedClasses: Bool = false
    /// Called after a successful save (the wizard advances on it).
    var onSaved: ((Term) -> Void)?

    @State private var name: String = ""
    @State private var hasDates = false
    @State private var startsOn = Date()
    @State private var endsOn = Date()
    @State private var keyDates: [TermKeyDate] = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameField
                    datesField
                    keyDatesField
                }
                .padding(24)
            }
        }
        .frame(width: 460, height: 560, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(adoptUndatedClasses ? "Date your term" : "Semester")
                    .atlasFont(size: 19, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(adoptUndatedClasses
                     ? "Your existing classes will move into this term."
                     : "Dates keep class meetings inside the semester; breaks stop them.")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
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

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WHAT DO YOU CALL IT").atlasCapsLabel()
            TextField("Fall 2026", text: $name)
                .atlasTextField(size: 15)
        }
    }

    private var datesField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WHEN IT RUNS").atlasCapsLabel()
            Toggle(isOn: $hasDates) {
                Text("I know the start and end dates")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            .toggleStyle(AtlasToggleStyle())

            if hasDates {
                HStack(alignment: .bottom, spacing: 14) {
                    labelledDate("FIRST DAY", $startsOn)
                    labelledDate("LAST DAY", $endsOn)
                    Spacer()
                }
            } else {
                Text("Without dates Atlas won't draw class meetings — you can add them later.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
    }

    private func labelledDate(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).atlasCapsLabel()
            DatePicker("", selection: value, displayedComponents: .date)
                .atlasDateField()
        }
    }

    private var keyDatesField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("KEY DATES").atlasCapsLabel()
                Spacer()
                Button {
                    keyDates.append(TermKeyDate(label: "", date: hasDates ? startsOn : Date(), kind: .other))
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus").atlasFont(size: 10, weight: .semibold)
                        Text("Add").atlasFont(size: 12, weight: .semibold, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

            if keyDates.isEmpty {
                Text("Add/drop deadline, holidays, spring break, finals. Atlas flags them on the calendar, and no class meets on a holiday or a break.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(keyDates.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField("Spring break", text: Binding(
                        get: { keyDates[i].label },
                        set: { keyDates[i].label = $0 }))
                        .atlasTextField()
                    DatePicker("", selection: Binding(
                        get: { keyDates[i].date },
                        set: { keyDates[i].date = $0 }), displayedComponents: .date)
                        .atlasDateField()
                    Picker("", selection: Binding(
                        get: { keyDates[i].kind ?? .other },
                        set: { keyDates[i].kind = $0 })) {
                            ForEach(Self.kindChoices, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 108)
                    Button { keyDates.remove(at: i) } label: {
                        Image(systemName: "minus.circle")
                            .atlasFont(size: 12)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The kinds a person actually types. `.other` is the catch-all; only holiday and
    /// break change behaviour (they stop class meetings), which the labels say plainly.
    private static let kindChoices: [(TermKeyDateKind, String)] = [
        (.classesBegin, "Classes begin"),
        (.classesEnd,   "Classes end"),
        (.addDrop,      "Add/drop"),
        (.holiday,      "No class"),
        (.breakPeriod,  "Break"),
        (.finals,       "Finals"),
        (.deadline,     "Deadline"),
        (.other,        "Other"),
    ]

    // MARK: - Load / save

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = term.name
        keyDates = term.keyDates
        if let s = term.startsOn, let e = term.endsOn {
            hasDates = true
            startsOn = s
            endsOn = e
        } else {
            // A blank term opens on a plausible 4-month window, still fully editable.
            startsOn = Date()
            endsOn = Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        var updated = term
        updated.name = trimmedName
        updated.startsOn = hasDates ? startsOn : nil
        updated.endsOn = hasDates ? endsOn : nil
        updated.keyDates = keyDates
            .filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.date < $1.date }
        state.saveTerm(updated)
        if adoptUndatedClasses { state.adoptUndatedClasses(into: updated) }
        onSaved?(updated)
        dismiss()
    }
}
