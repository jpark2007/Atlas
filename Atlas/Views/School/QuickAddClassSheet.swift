import SwiftUI
import AtlasCore

/// "+" in the School header — one class, typed by hand, in about ten seconds.
///
/// Deliberately NOT the wizard: the wizard is the setup flow for a whole semester and
/// asks which door your schedule came through. Adding the one class you forgot is a
/// different job, and being asked "are you a student?" again to do it is absurd. The
/// wizard stays behind the zero state and the ⋯ menu.
///
/// Meeting times are optional here — a class with a name is already useful, and the same
/// day/time controls live on the class page (`MeetingPatternSheet`) for later.
struct QuickAddClassSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// The term the class is filed under; nil ⇒ `addClass` uses the active one.
    let term: Term?

    @State private var name = ""
    @State private var code = ""
    @State private var colorToken = ""
    @State private var meets = false
    @State private var weekdays: Set<Int> = []
    @State private var start = Date()
    @State private var end = Date()
    @State private var location = ""
    @State private var didLoad = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameAndCode
                    colorField
                    meetingField
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 470, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Pre-picked, not asked for: the next unused hue, changeable in one click.
            colorToken = state.nextClassColorToken()
            start = SchoolCalendar.time("09:00", on: Date()) ?? Date()
            end = SchoolCalendar.time("09:50", on: Date()) ?? Date()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a class")
                    .atlasFont(size: 19, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(term.map { "It goes into \($0.name)." } ?? "It goes into this semester.")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
            Button("Add") { save() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(trimmedName.isEmpty ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.accentText)
                .disabled(trimmedName.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    // MARK: - Fields

    private var nameAndCode: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("CLASS").atlasCapsLabel()
                TextField("Organic Chemistry", text: $name)
                    .atlasTextField(size: 15)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("CODE (OPTIONAL)").atlasCapsLabel()
                TextField("CHEM 201", text: $code)
                    .atlasTextField()
                    .frame(width: 130)
            }
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("COLOR").atlasCapsLabel()
            HStack(spacing: 8) {
                ForEach(AtlasTheme.Colors.classPalette.map { ColorToken.token(for: $0) }, id: \.self) { token in
                    let picked = token == colorToken
                    Button { colorToken = token } label: {
                        Circle()
                            .fill(ColorToken.color(for: token))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(AtlasTheme.Colors.textPrimary,
                                                           lineWidth: picked ? AtlasTheme.rule : 0)
                                .padding(-3))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 3)
        }
    }

    private var meetingField: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("WHEN IT MEETS").atlasCapsLabel()
            Toggle(isOn: $meets) {
                Text("It meets at a set time each week")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            .toggleStyle(AtlasToggleStyle())

            if meets {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        dayToggle(day)
                    }
                    Spacer()
                }
                HStack(alignment: .bottom, spacing: 12) {
                    labelledTime("FROM", $start)
                    labelledTime("TO", $end)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("WHERE (OPTIONAL)").atlasCapsLabel()
                        TextField("Tech Hall 204", text: $location)
                            .atlasTextField(size: 12)
                    }
                }
            } else {
                Text("Skip it — you can add times from the class page, a syllabus scan, or your school's calendar.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labelledTime(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).atlasCapsLabel()
            DatePicker("", selection: value, displayedComponents: .hourAndMinute)
                .atlasDateField()
        }
    }

    private func dayToggle(_ day: Int) -> some View {
        let on = weekdays.contains(day)
        return Button {
            if on { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(MeetingPatternFormat.weekdayInitials[day])
                .atlasMono(size: 11, weight: .semibold)
                .foregroundStyle(on ? AtlasTheme.Colors.bgBase : AtlasTheme.Colors.textSecondary)
                .frame(width: 30, height: 26)
                .background(on ? AtlasTheme.Colors.textPrimary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.border, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let created = state.addClass(name: trimmedName,
                                           code: trimmedCode.isEmpty ? nil : trimmedCode,
                                           termID: term?.id,
                                           colorToken: colorToken.isEmpty ? nil : colorToken)
        else { return }

        // A pattern with no day selected can never produce a meeting — store nothing
        // rather than a shape that draws nothing.
        if meets, !weekdays.isEmpty {
            let where_ = location.trimmingCharacters(in: .whitespaces)
            state.setMeetingPattern(projectID: created.id,
                                    blocks: [MeetingBlock(weekdays: weekdays.sorted(),
                                                          start: Self.hhmm(start),
                                                          end: Self.hhmm(end),
                                                          location: where_.isEmpty ? nil : where_)],
                                    meetingInfo: nil)
        }
        state.route = .project(created.id)
        dismiss()
    }

    private static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
