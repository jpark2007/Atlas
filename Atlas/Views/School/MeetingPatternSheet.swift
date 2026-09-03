import SwiftUI
import AtlasCore

/// Edit when a class meets — weekday toggles, a start and an end, and where.
///
/// This is the FALLBACK door, not the main path: the schedule is meant to arrive from
/// Canvas, a school calendar link or a scan. It exists because sometimes none of those
/// have it, and because a wrong imported time has to be fixable. Deliberately not a
/// timetable builder — one row per block, no rotation days.
struct MeetingPatternSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var blocks: [DraftBlock] = []
    @State private var meetingNote = ""
    @State private var didLoad = false

    /// A block being edited: weekdays plus real `Date`s for the pickers, converted back
    /// to the stored "HH:mm" wall clock on save.
    struct DraftBlock: Identifiable {
        let id = UUID()
        var weekdays: Set<Int> = []
        var start = Date()
        var end = Date()
        var location = ""
        /// The dated window an imported block carries (`MeetingBlock.firstDate` /
        /// `lastDate`). Editing the times must not widen a September class back across
        /// the whole term, so the window rides along untouched; a row added here has none.
        var firstDate: Date?
        var lastDate: Date?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach($blocks) { $block in
                        blockEditor($block)
                    }
                    Button { blocks.append(defaultBlock()) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").atlasFont(size: 10, weight: .semibold)
                            Text("Another meeting time").atlasFont(size: 12, weight: .semibold, design: .rounded)
                        }
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("NOTE (OPTIONAL)").atlasCapsLabel()
                        TextField("Lab alternates weeks", text: $meetingNote)
                            .textFieldStyle(.plain)
                            .atlasFont(size: 13, design: .rounded)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 470, height: 480, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("When does \(project.name) meet?")
                    .atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text("Meetings are drawn on your calendar inside the term, and count as busy time.")
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
                .foregroundStyle(AtlasTheme.Colors.accentText)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    private func blockEditor(_ block: Binding<DraftBlock>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    dayToggle(day, block)
                }
                Spacer()
                Button { blocks.removeAll { $0.id == block.wrappedValue.id } } label: {
                    Image(systemName: "minus.circle")
                        .atlasFont(size: 12)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                DatePicker("From", selection: block.start, displayedComponents: .hourAndMinute)
                DatePicker("to", selection: block.end, displayedComponents: .hourAndMinute)
            }
            .datePickerStyle(.compact)
            .atlasFont(size: 13, weight: .medium, design: .rounded)

            TextField("Where (optional)", text: block.location)
                .textFieldStyle(.plain)
                .atlasFont(size: 13, design: .rounded)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
        }
        .padding(.bottom, 6)
        .atlasHairlineBelow()
    }

    private func dayToggle(_ day: Int, _ block: Binding<DraftBlock>) -> some View {
        let on = block.wrappedValue.weekdays.contains(day)
        return Button {
            if on { block.wrappedValue.weekdays.remove(day) } else { block.wrappedValue.weekdays.insert(day) }
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

    // MARK: - Load / save

    private func defaultBlock() -> DraftBlock {
        var b = DraftBlock()
        b.start = SchoolCalendar.time("09:00", on: Date()) ?? Date()
        b.end = SchoolCalendar.time("09:50", on: Date()) ?? Date()
        return b
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        meetingNote = project.meetingInfo ?? ""
        blocks = project.meetingPattern.map { stored in
            var b = DraftBlock()
            b.weekdays = Set(stored.weekdays)
            b.start = SchoolCalendar.time(stored.start, on: Date()) ?? Date()
            b.end = SchoolCalendar.time(stored.end, on: Date()) ?? Date()
            b.location = stored.location ?? ""
            b.firstDate = stored.firstDate
            b.lastDate = stored.lastDate
            return b
        }
        if blocks.isEmpty { blocks = [defaultBlock()] }
    }

    private func save() {
        // A block with no day selected isn't a schedule — drop it rather than storing a
        // pattern that can never produce a meeting.
        let stored = blocks.compactMap { draft -> MeetingBlock? in
            guard !draft.weekdays.isEmpty else { return nil }
            let location = draft.location.trimmingCharacters(in: .whitespaces)
            return MeetingBlock(weekdays: draft.weekdays.sorted(),
                                start: Self.hhmm(draft.start),
                                end: Self.hhmm(draft.end),
                                location: location.isEmpty ? nil : location,
                                firstDate: draft.firstDate,
                                lastDate: draft.lastDate)
        }
        state.setMeetingPattern(projectID: project.id, blocks: stored,
                                meetingInfo: meetingNote.trimmingCharacters(in: .whitespaces),
                                source: .manual)
        dismiss()
    }

    /// The picker's instant reduced to the wall clock the block stores.
    private static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
