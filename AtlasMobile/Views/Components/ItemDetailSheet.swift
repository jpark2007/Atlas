import SwiftUI
import AtlasCore

/// The single tap-to-open sheet for a task or an event.
///
/// It OPENS as a compact, read-only card (variant 6C of
/// `docs/specs/redesign-2026-08/ui-density-syllabus-ideas.html`): title + class chip,
/// a two-column facts row, a notes snippet and the linked note — everything above the
/// fold, no scrolling. **Edit** swaps in the full editable form (unchanged); **Done**
/// dismisses. Items that can't be edited (Apple/Canvas events) show no Edit button and
/// keep their true source label — attribution is never guessed (CLAUDE.md rule 5).
///
/// Editorial field style in the edit form — a caps label over a control, hairline
/// below — mirrors `ManualAddSheet`.
struct ItemDetailSheet: View {

    /// What this sheet is showing. Identifiable so it drives `.sheet(item:)`.
    enum Detail: Identifiable {
        case task(TaskItem)
        case event(CalendarEvent)

        var id: UUID {
            switch self {
            case .task(let t):  return t.id
            case .event(let e): return e.id
            }
        }
    }

    let detail: Detail

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    // Shared editable fields
    @State private var title: String
    @State private var spaceName: String
    @State private var notes: String
    // Task-only
    @State private var projectName: String
    @State private var hasDue: Bool
    @State private var dueDay: Date
    @State private var setTime: Bool
    @State private var timeOfDay: Date
    // Event-only
    @State private var startDay: Date
    @State private var startTime: Date
    /// The last day the event covers, read INCLUSIVELY — an all-day Mon–Wed event shows
    /// Wednesday here even though it is stored with an exclusive Thursday end.
    @State private var endDay: Date
    @State private var durationMin: Int

    @State private var showDeleteConfirm = false

    /// False = the compact 6C read card the sheet opens as; true = the full edit form.
    @State private var isEditing = false
    /// The read card is a half-sheet; editing grows it so a form isn't a clipped slab.
    @State private var detent: PresentationDetent = .medium

    /// Includes the event's own length even when it's off the ladder, so a synced
    /// 3h event stays selectable instead of being truncated by the first tap.
    private var durations: [Int] { EventDuration.options(including: durationMin) }

    init(detail: Detail) {
        self.detail = detail
        switch detail {
        case .task(let t):
            _title = State(initialValue: t.title)
            _spaceName = State(initialValue: t.spaceName)
            _notes = State(initialValue: t.notes)
            _projectName = State(initialValue: t.projectName)
            let due = t.dueDate
            let base = due ?? Date()
            _hasDue = State(initialValue: due != nil)
            _dueDay = State(initialValue: base)
            let c = Calendar.current.dateComponents([.hour, .minute], from: base)
            _setTime = State(initialValue: due != nil && (c.hour != 0 || c.minute != 0))
            _timeOfDay = State(initialValue: base)
            // Event fields unused for a task.
            _startDay = State(initialValue: Date())
            _startTime = State(initialValue: Date())
            _endDay = State(initialValue: Date())
            _durationMin = State(initialValue: 60)
        case .event(let e):
            _title = State(initialValue: e.title)
            _spaceName = State(initialValue: e.spaceName)
            _notes = State(initialValue: e.notes ?? "")
            // The day picker shows the date the event *reads* as. For an all-day event that
            // is its bucket date, not its UTC-midnight anchor (which reads as the day before).
            _startDay = State(initialValue: e.bucketDate(in: .current))
            _startTime = State(initialValue: e.start)
            // A timed event splits into a clock length + the day its end lands on; an all-day
            // one is stored with an EXCLUSIVE end, so the last day it covers is the day before.
            let split = EventDuration.split(start: e.start, end: e.end, calendar: .current)
            _endDay = State(initialValue: e.isAllDay
                            ? AllDayDate.localDay(of: AllDayDate.utc.date(byAdding: .day, value: -1, to: e.end) ?? e.end,
                                                  calendar: .current)
                            : split.endDay)
            _durationMin = State(initialValue: split.minutes)
            // Task fields unused for an event.
            _projectName = State(initialValue: "")
            _hasDue = State(initialValue: false)
            _dueDay = State(initialValue: Date())
            _setTime = State(initialValue: false)
            _timeOfDay = State(initialValue: Date())
        }
    }

    var body: some View {
        Group {
            if isEditing {
                editScroll
            } else {
                readCard
            }
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: startDay) { oldStart, newStart in
            // Moving an event carries its span along, and the end can never precede the start.
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: oldStart),
                                          to: cal.startOfDay(for: newStart)).day ?? 0
            if days != 0 { endDay = cal.date(byAdding: .day, value: days, to: endDay) ?? endDay }
            if endDay < cal.startOfDay(for: newStart) { endDay = newStart }
        }
        .confirmationDialog("Delete this \(isTask ? "task" : "event")?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
        }
    }

    // MARK: - Read card (variant 6C — no scroll)

    private var readCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            readHeader

            if let moved = dueMovedFrom {
                dueMovedChip(from: moved)
                    .padding(.top, 10)
            }

            if let note = sourceNote {
                Text(note)
                    .edCapsLabel()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            readRule
            factsRow

            if !displayNotes.isEmpty {
                readRule
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").edCapsLabel()
                    Text(displayNotes)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let note = linkedNote {
                linkedNoteRow(note).padding(.top, 16)
            }

            Spacer(minLength: 20)
            readCTA
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Colour dot · title · class-or-space chip with its source · a NOW pill when live.
    private var readHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(accentDotColor)
                .frame(width: 9, height: 9)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .tracking(-0.38)        // −0.02em × 19
                    .foregroundStyle(MobileTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    if !contextLabel.isEmpty {
                        HStack(spacing: 5) {
                            Circle().fill(accentDotColor).frame(width: 6, height: 6)
                            Text(contextLabel)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(MobileTheme.ink)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                                .fill(accentDotColor.opacity(0.14))
                        )
                    }
                    if let origin = originLabel {
                        Text(origin)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(MobileTheme.faint)
                    }
                }
            }

            Spacer(minLength: 8)

            if isNow {
                Text("Now")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(MobileTheme.accentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                            .fill(MobileTheme.accent.opacity(0.16))
                    )
                    .padding(.top, 2)
            }
        }
    }

    /// The two-column facts row. Column two is the item's length (an event) or the day it
    /// was planned for (a task) — a "Where" needs an event location field, which Atlas
    /// doesn't store yet; labelling anything else "Where" would be a lie.
    private var factsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            factColumn(primaryFactLabel, primaryFact)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let (label, value) = secondaryFact {
                factColumn(label, value).frame(width: 96, alignment: .leading)
            }
        }
    }

    private func factColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).edCapsLabel()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkedNoteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MobileTheme.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title.isEmpty ? "Untitled note" : note.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .lineLimit(1)
                Text("Linked note")
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .fill(MobileTheme.ink.opacity(0.04))
        )
    }

    private var readCTA: some View {
        HStack(spacing: 12) {
            if isEditable {
                Button {
                    detent = .large
                    isEditing = true
                } label: {
                    Text("Edit")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
            }

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEditable ? MobileTheme.muted : MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    private var readRule: some View {
        Rectangle()
            .fill(MobileTheme.hairline)
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    // MARK: - Read-card values

    private var displayTitle: String {
        switch detail {
        case .task(let t):  return t.title
        case .event(let e): return e.title
        }
    }

    /// The due date this task carried before a Canvas re-sync moved it (migration 0047),
    /// nil for everything else — the chip is task-only.
    private var dueMovedFrom: Date? {
        guard case .task(let t) = detail else { return nil }
        return t.dueMovedFrom
    }

    /// "Due date moved from <date>" — Canvas re-synced this assignment to a new due date;
    /// the user's own scheduled work block was left untouched, so this is the only signal
    /// the plan may no longer match the deadline. Dismissible; clears and persists
    /// immediately, independent of the edit form's Save.
    private func dueMovedChip(from moved: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
            Text("Due date moved from \(moved.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
            Button {
                guard case .task(var t) = detail else { return }
                t.dueMovedFrom = nil
                Task { await store.updateTask(t) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(MobileTheme.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .fill(MobileTheme.warning.opacity(0.14))
        )
    }

    private var displayNotes: String {
        switch detail {
        case .task(let t):  return t.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        case .event(let e): return (e.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The class (project) when there is one, else the space — the chip's text.
    private var contextLabel: String {
        switch detail {
        case .task(let t):  return t.projectName.isEmpty ? t.spaceName : t.projectName
        case .event(let e):
            if let id = e.projectID,
               let p = store.snapshot.projects.first(where: { $0.id == id }) { return p.name }
            return e.spaceName
        }
    }

    private var accentDotColor: Color {
        switch detail {
        case .task(let t):  return t.spaceColor
        case .event(let e): return e.color
        }
    }

    /// "from Canvas" / "from Google Calendar" / "from BIO 101 syllabus.pdf" — never for
    /// an Atlas-native item, and always the source the item actually carries (rule 5).
    /// A syllabus scan names the document it read; that beats a synced-feed label only
    /// because nothing carries both.
    private var originLabel: String? {
        if let scan = store.scan(scanID) { return "from \(scan.fileName)" }
        switch detail {
        case .task(let t):  return t.canvasUID != nil ? "from Canvas" : nil
        case .event(let e): return e.source == .atlas ? nil : "from \(e.source.displayName)"
        }
    }

    /// The scan receipt this item points at, if any.
    private var scanID: UUID? {
        switch detail {
        case .task(let t):  return t.scanID
        case .event(let e): return e.scanID
        }
    }

    /// The locked-source caps line, same copy the edit form and the Mac use.
    private var sourceNote: String? {
        if isCanvasTask || readOnlyEvent?.source == .canvas {
            return "From Canvas — synced automatically. Schedule it; title and dates update from your feed."
        }
        if let e = readOnlyEvent { return "From \(e.source.displayName) — shown, not editable" }
        return nil
    }

    private var primaryFactLabel: String { isTask ? "Due" : "When" }

    private var primaryFact: String {
        switch detail {
        case .task:         return dueDisplay
        case .event(let e): return whenText(e)
        }
    }

    /// Column two: an event's length, or the day a task is planned to be worked.
    private var secondaryFact: (String, String)? {
        switch detail {
        case .task(let t):
            guard let at = t.scheduledAt else { return nil }
            let f = DateFormatter(); f.dateFormat = "EEE · h:mm a"
            return ("Planned", f.string(from: at))
        case .event(let e):
            return ("Length", e.isAllDay ? "All-day" : e.durationLabel)
        }
    }

    /// An event happening right now — the NOW pill.
    private var isNow: Bool {
        guard case .event(let e) = detail, !e.isAllDay else { return false }
        let now = Date()
        return e.start <= now && now < e.end
    }

    private var linkedNote: Note? {
        let id: UUID?
        switch detail {
        case .task(let t):  id = t.noteID
        case .event(let e): id = e.noteID
        }
        guard let id else { return nil }
        return store.snapshot.notes.first { $0.id == id }
    }

    /// "Tue, Sep 1 · 2:00–3:20 PM"; an all-day event names its day (or its span).
    private func whenText(_ e: CalendarEvent) -> String {
        let cal = Calendar.current
        let day = DateFormatter(); day.dateFormat = "EEE, MMM d"
        if e.isAllDay {
            let bucket = e.bucketDate(in: cal)
            // Stored end is EXCLUSIVE — the last day covered is the day before it.
            let last = AllDayDate.localDay(of: AllDayDate.utc.date(byAdding: .day, value: -1, to: e.end) ?? e.end,
                                           calendar: cal)
            if cal.isDate(bucket, inSameDayAs: last) { return "\(day.string(from: bucket)) · All-day" }
            return "\(day.string(from: bucket)) – \(day.string(from: last))"
        }
        let clock = DateFormatter(); clock.dateFormat = "h:mm a"
        let span = "\(clock.string(from: e.start))–\(clock.string(from: e.end))"
        if cal.isDate(e.start, inSameDayAs: e.end) { return "\(day.string(from: e.start)) · \(span)" }
        return "\(day.string(from: e.start)) \(clock.string(from: e.start)) – \(day.string(from: e.end)) \(clock.string(from: e.end))"
    }

    // MARK: - Editable

    private var editScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(isTask ? "Task" : "Event")
                    .edScreenTitle()
                    .padding(.bottom, 24)

                editableFields
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
    }


    @ViewBuilder
    private var editableFields: some View {
        if isGoogleEvent {
            Text("Syncs with Google Calendar")
                .edCapsLabel()
                .padding(.bottom, 8)
        } else if isCanvasTask {
            // Canvas owns title + due (re-sync overwrites only those); scheduling,
            // notes, space and project stay user-editable. Same copy the Mac uses.
            Text("From Canvas — synced automatically. Schedule it; title and dates update from your feed.")
                .edCapsLabel()
                .padding(.bottom, 8)
        }

        if isCanvasTask {
            labeledRow("Title", title)
        } else {
            field("Title") { titleField }
        }
        field("Space") { spacePicker }

        if isTask {
            field("Project") { projectPicker }
            if isCanvasTask {
                labeledRow("Due date", dueDisplay)
            } else {
                dueSection
            }
        } else {
            startSection
            field("Ends") { endDayPicker }
            if isAllDayEvent {
                labeledRow("Duration", "All-day")
            } else {
                field("Duration") { durationPicker }
            }
        }

        field("Notes") { notesEditor }
    }

    private var titleField: some View {
        TextField("", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
    }

    private var spacePicker: some View {
        Menu {
            ForEach(spaces) { space in
                Button {
                    spaceName = space.name
                    // If the picked project no longer belongs to the new space, drop it.
                    if !projectBelongsToSelectedSpace { projectName = "" }
                } label: {
                    if space.name.caseInsensitiveCompare(spaceName) == .orderedSame {
                        Label(space.name, systemImage: "checkmark")
                    } else {
                        Text(space.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let space = selectedSpace {
                    Circle().fill(space.color).frame(width: 9, height: 9)
                    Text(space.name)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                } else {
                    Text(spaceName.isEmpty ? "No space" : spaceName)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    /// Task due — day + optional time (ManualAddSheet's `dueSection` pattern).
    private var dueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $hasDue.animation()) {
                Text("Due date").edCapsLabel()
            }
            .tint(MobileTheme.ink)
            .padding(.vertical, 14)
            .edHairlineBelow()

            if hasDue {
                DatePicker("", selection: $dueDay, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(MobileTheme.accentText)
                    .padding(.vertical, 8)

                Toggle(isOn: $setTime.animation()) {
                    Text("Set a time").edCapsLabel()
                }
                .tint(MobileTheme.ink)
                .padding(.vertical, 14)
                .edHairlineBelow()

                if setTime {
                    DatePicker("", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    /// Event start — day (graphical) + time (wheel). An all-day event has no
    /// clock time, so it picks a day only.
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start").edCapsLabel()
            DatePicker("", selection: $startDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(MobileTheme.accentText)
            if !isAllDayEvent {
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    /// The last day the event covers — a compact date pill, so a conference or a trip can
    /// run past its start day. Inclusive: picking Wednesday means the event ends Wednesday.
    private var endDayPicker: some View {
        DatePicker("", selection: $endDay,
                   in: Calendar.current.startOfDay(for: startDay)...,
                   displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(MobileTheme.accentText)
    }

    private var durationPicker: some View {
        Menu {
            ForEach(durations, id: \.self) { m in
                Button { durationMin = m } label: {
                    if m == durationMin {
                        Label(EventDuration.label(m), systemImage: "checkmark")
                    } else {
                        Text(EventDuration.label(m))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(EventDuration.label(durationMin))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    /// Project — a Menu of the selected space's projects plus "None". Mirrors the
    /// space picker; keeps the current value as the label even if it's off-list so
    /// we never silently drop a task's existing project.
    private var projectPicker: some View {
        Menu {
            Button { projectName = "" } label: {
                if projectName.isEmpty {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }
            ForEach(spaceProjects) { project in
                Button { projectName = project.name } label: {
                    if project.name.caseInsensitiveCompare(projectName) == .orderedSame {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(projectName.isEmpty ? "None" : projectName)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(projectName.isEmpty ? MobileTheme.faint : MobileTheme.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    private var notesEditor: some View {
        TextEditor(text: $notes)
            .scrollContentBackground(.hidden)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .frame(height: 100)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        field(label) {
            Text(value)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
            Button(action: save) {
                Text("Save")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            if canDelete {
                Button { showDeleteConfirm = true } label: {
                    Text("Delete")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            // Backs out of the form to the read card the sheet opened as — the sheet
            // itself is dismissed with Done there.
            Button {
                detent = .medium
                isEditing = false
            } label: {
                Text("Cancel")
                    .edCapsLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Field helper (editorial: caps label over a control, hairline below)

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).edCapsLabel()
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    // MARK: - Derived

    private var isTask: Bool { if case .task = detail { return true }; return false }

    private var isAllDayEvent: Bool {
        if case .event(let e) = detail, e.isAllDay { return true }
        return false
    }

    private var isGoogleEvent: Bool {
        if case .event(let e) = detail, e.source == .google { return true }
        return false
    }

    /// A Canvas-synced task (assignment): title + due are server-owned and lock,
    /// everything else stays editable (mirrors Mac `TaskDetailView.isCanvasTask`).
    private var isCanvasTask: Bool {
        if case .task(let t) = detail { return t.canvasUID != nil }
        return false
    }

    /// Due text for a task — date label plus clock time when the due carries one
    /// (mirrors Mac `TaskDetailView.dueChipLabel`). Also the locked value a Canvas
    /// task shows in the edit form.
    private var dueDisplay: String {
        guard case .task(let t) = detail, let due = t.dueDate else { return "No due date" }
        // An all-day Canvas due names a DATE — the compact label already reads it off the
        // right day; printing its raw UTC-midnight clock would say the wrong evening.
        guard !t.allDay else { return t.dueLabel }
        let cal = Calendar.current
        let h = cal.component(.hour, from: due), m = cal.component(.minute, from: due)
        guard h != 0 || m != 0 else { return t.dueLabel }
        let f = DateFormatter(); f.dateFormat = m == 0 ? "h a" : "h:mm a"
        return "\(t.dueLabel) · \(f.string(from: due))"
    }

    /// Atlas and Google events edit the same way — server-side sync PATCHes Atlas
    /// edits back to Google and tombstones propagate deletes. Apple and Canvas
    /// events stay read-only.
    private var isEditable: Bool {
        switch detail {
        case .task:          return true
        case .event(let e):  return e.source == .atlas || e.source == .google
        }
    }

    private var canDelete: Bool {
        switch detail {
        case .task:          return true
        case .event(let e):  return e.source == .atlas || e.source == .google
        }
    }

    /// External read-only events render the labeled read-only fields. Apple and
    /// Canvas are both fully read-only (Canvas is server-owned via its ICS feed).
    private var readOnlyEvent: CalendarEvent? {
        if case .event(let e) = detail, e.source == .apple || e.source == .canvas { return e }
        return nil
    }

    private var spaces: [Space] { store.snapshot.spaces }
    private var selectedSpace: Space? {
        spaces.first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }
    }

    /// Projects belonging to the currently-selected space (case-insensitive), the
    /// same match `MobileStore.contextSpaces` uses to re-nest projects.
    private var spaceProjects: [Project] {
        store.snapshot.projects.filter {
            $0.spaceName.caseInsensitiveCompare(spaceName) == .orderedSame
        }
    }

    /// True when the picked project is empty or lives in the selected space.
    private var projectBelongsToSelectedSpace: Bool {
        projectName.isEmpty || spaceProjects.contains {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }
    }

    // MARK: - Commit

    private func save() {
        let cal = Calendar.current
        switch detail {
        case .task(let t):
            var updated = t
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let space = selectedSpace {
                updated.spaceName = space.name
                updated.spaceColor = space.color
            }
            updated.projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.projectID = store.projectID(spaceName: updated.spaceName,
                                                projectName: updated.projectName)
            updated.notes = notes
            if hasDue {
                let day = cal.startOfDay(for: dueDay)
                if setTime {
                    let c = cal.dateComponents([.hour, .minute], from: timeOfDay)
                    updated.dueDate = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day)
                } else {
                    updated.dueDate = day
                }
            } else {
                updated.dueDate = nil
            }
            updated.dueLabel = TaskItem.dueLabel(for: updated.dueDate)
            Task { await store.updateTask(updated) }

        case .event(let e):
            var updated = e
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let space = selectedSpace {
                updated.spaceName = space.name
                updated.color = space.color
            }
            updated.notes = notes.isEmpty ? nil : notes
            if e.isAllDay {
                // All-day events carry no clock time — stamping one would turn them into a
                // timed block. Both ends are re-anchored to UTC midnight of the picked day
                // (`AllDayDate`), and the picked end day is INCLUSIVE, so the stored end —
                // which is exclusive — is the day after it.
                let start = AllDayDate.anchor(forDayOf: startDay, in: cal)
                let lastDay = AllDayDate.anchor(forDayOf: max(endDay, startDay), in: cal)
                updated.start = start
                updated.end = AllDayDate.utc.date(byAdding: .day, value: 1, to: lastDay) ?? start
            } else {
                let day = cal.startOfDay(for: startDay)
                let c = cal.dateComponents([.hour, .minute], from: startTime)
                let start = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? e.start
                updated.start = start
                // Duration sets the clock time it ends at; the end day carries it onto a
                // later date, so a multi-day event is simply end > start on another day.
                updated.end = EventDuration.end(start: start, minutes: durationMin,
                                                endDay: endDay, calendar: cal)
            }
            Task { await store.updateEvent(updated) }
        }
        MobileTheme.Haptic.success()
        dismiss()
    }

    private func performDelete() {
        switch detail {
        case .task(let t):  Task { await store.deleteTask(id: t.id) }
        case .event(let e): Task { await store.deleteEvent(id: e.id) }
        }
        dismiss()
    }
}
