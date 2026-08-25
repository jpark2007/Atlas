import SwiftUI
import AtlasCore

/// Name a term, date it, and list its Key Dates — the iOS twin of the Mac
/// `TermEditorSheet`, in the app's editorial sheet idiom (footer buttons, no toolbar).
///
/// Key Dates are the cheap differentiator: competitors make students type classes-begin,
/// add/drop and every break by hand somewhere they'll never look again. Here they land on
/// the term, the calendar flags them, and holidays/breaks additionally stop class meetings
/// from being drawn (`SchoolCalendar.isBreakDay`).
struct TermEditorSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    /// The term being edited — a brand-new one when it isn't in the snapshot yet.
    let term: Term
    /// True for the migration prompt: saving also files every undated class into this term.
    var adoptUndatedClasses: Bool = false
    /// Called after a successful save (the wizard advances on it).
    var onSaved: ((Term) -> Void)?

    @State private var name = ""
    @State private var hasDates = false
    @State private var startsOn = Date()
    @State private var endsOn = Date()
    @State private var keyDates: [TermKeyDate] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                field("What do you call it") { nameField }
                field("When it runs") { datesField }
                field("Key dates") { keyDatesField }
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(adoptUndatedClasses ? "Date your term" : "Semester").edScreenTitle()
            Text(adoptUndatedClasses
                 ? "Your existing classes will move into this term."
                 : "Dates keep class meetings inside the semester; breaks stop them.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Fields

    private var nameField: some View {
        TextField("Fall 2026", text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
    }

    @ViewBuilder
    private var datesField: some View {
        Toggle(isOn: $hasDates) {
            Text("I know the start and end dates")
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
        }
        .tint(MobileTheme.ink)

        if hasDates {
            DatePicker("First day", selection: $startsOn, displayedComponents: .date)
            DatePicker("Last day", selection: $endsOn, displayedComponents: .date)
        } else {
            Text("Without dates Atlas won't draw class meetings — you can add them later.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var keyDatesField: some View {
        if keyDates.isEmpty {
            Text("Add/drop deadline, holidays, spring break, finals. Atlas flags them on the calendar, and no class meets on a holiday or a break.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(keyDates.indices, id: \.self) { i in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Spring break", text: Binding(get: { keyDates[i].label },
                                                            set: { keyDates[i].label = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 15.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .tint(MobileTheme.accent)
                    Button { keyDates.remove(at: i) } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MobileTheme.faint)
                    }
                    .buttonStyle(.plain)
                }
                DatePicker("On", selection: Binding(get: { keyDates[i].date },
                                                    set: { keyDates[i].date = $0 }),
                           displayedComponents: .date)
                Picker("What kind", selection: Binding(get: { keyDates[i].kind ?? .other },
                                                       set: { keyDates[i].kind = $0 })) {
                    ForEach(Self.kindChoices, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.menu)
                .tint(MobileTheme.accentText)
            }
            .padding(.bottom, 6)
            .edHairlineBelow()
        }

        Button {
            keyDates.append(TermKeyDate(label: "", date: hasDates ? startsOn : Date(), kind: .other))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                Text("Add a key date").font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(MobileTheme.accentText)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
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

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            Button { save() } label: {
                Text("Save")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(trimmedName.isEmpty ? MobileTheme.faint : MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            .disabled(trimmedName.isEmpty)

            Button { dismiss() } label: {
                Text("Cancel").edCapsLabel().frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
        .padding(.bottom, 40)
    }

    /// A caps-labelled field group — the app's editorial sheet idiom.
    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).edCapsLabel()
            content()
        }
        .padding(.bottom, 26)
    }

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
        store.saveTerm(updated)
        if adoptUndatedClasses { store.adoptUndatedClasses(into: updated) }
        MobileTheme.Haptic.success()
        onSaved?(updated)
        dismiss()
    }
}
