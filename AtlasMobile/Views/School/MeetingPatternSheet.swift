import SwiftUI
import AtlasCore

/// Edit when a class meets — weekday toggles, a start and an end, and where.
///
/// This is the FALLBACK door, not the main path: the schedule is meant to arrive from
/// Canvas, a school calendar link or a syllabus scan. It exists because sometimes none
/// of those have it, and because a wrong imported time has to be fixable. Deliberately
/// not a timetable builder — one row per block, no rotation days.
struct MeetingPatternSheet: View {
    @EnvironmentObject private var store: MobileStore
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                ForEach($blocks) { $block in
                    blockEditor($block)
                }

                Button { blocks.append(defaultBlock()) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Another meeting time")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(MobileTheme.accentText)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Note (optional)").edCapsLabel()
                    TextField("Lab alternates weeks", text: $meetingNote)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15.5, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .tint(MobileTheme.accent)
                }
                .padding(.top, 28)

                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When does it meet?").edScreenTitle()
            Text("Meetings are drawn on your calendar inside the term, and count as busy time.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 24)
    }

    private func blockEditor(_ block: Binding<DraftBlock>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    dayToggle(day, block)
                }
            }
            DatePicker("From", selection: block.start, displayedComponents: .hourAndMinute)
            DatePicker("To", selection: block.end, displayedComponents: .hourAndMinute)
            HStack(spacing: 10) {
                TextField("Where (optional)", text: block.location)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .tint(MobileTheme.accent)
                Button { blocks.removeAll { $0.id == block.wrappedValue.id } } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(MobileTheme.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 14)
        .edHairlineBelow()
        .padding(.bottom, 14)
    }

    /// A thumb-sized day chip — filled ink when on, hairline outline when off.
    private func dayToggle(_ day: Int, _ block: Binding<DraftBlock>) -> some View {
        let on = block.wrappedValue.weekdays.contains(day)
        return Button {
            MobileTheme.Haptic.selection()
            if on { block.wrappedValue.weekdays.remove(day) } else { block.wrappedValue.weekdays.insert(day) }
        } label: {
            Text(MeetingPatternFormat.weekdayInitials[day])
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(on ? MobileTheme.bg : MobileTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(on ? MobileTheme.ink : Color.clear,
                            in: RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                    .strokeBorder(MobileTheme.hairline, lineWidth: on ? 0 : 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button { save() } label: {
                Text("Save")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Text("Cancel").edCapsLabel().frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
        .padding(.bottom, 40)
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
        store.setMeetingPattern(projectID: project.id, blocks: stored,
                                meetingInfo: meetingNote.trimmingCharacters(in: .whitespaces))
        MobileTheme.Haptic.success()
        dismiss()
    }

    /// The picker's instant reduced to the wall clock the block stores.
    private static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
