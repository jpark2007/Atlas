import SwiftUI
import AtlasCore

/// Full-page detail / edit view for a calendar item — opened by clicking any tile or agenda
/// row. One surface for Atlas events, scheduled-task work-blocks, and read-only external
/// items; the mode is read from the item's own flags (never inferred). A work-block IS a
/// task, so editing one writes through to the task (and its Google mirror), never `events`.
struct CalendarEventDetailView: View {
    @EnvironmentObject var state: AppState
    let item: CalendarEvent

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var descriptionText: String
    @State private var selectedSpaceName: String
    @State private var noteID: UUID?
    @State private var editingNote: Note?
    @State private var showRefPicker = false
    @State private var referenceSelection: Set<UUID> = []
    /// The edited event, parked while the user picks how far the change reaches.
    /// Non-nil ⇒ the scope dialog is up; nothing is written until they choose.
    @State private var pendingSeriesEdit: CalendarEvent?
    @State private var confirmingSeriesDelete = false

    init(item: CalendarEvent) {
        self.item = item
        _title = State(initialValue: item.title)
        // An all-day event is anchored at UTC midnight (`AllDayDate`); the date field and the
        // read-only label speak local dates, so both are shown the day the event NAMES rather
        // than the raw instant — which reads as the previous evening west of Greenwich.
        _start = State(initialValue: item.isAllDay
                       ? AllDayDate.localDay(of: item.start, calendar: .current)
                       : item.start)
        // The stored all-day end is EXCLUSIVE (Mon–Wed ends Thu 00:00Z); the field and the
        // read-only label speak the INCLUSIVE last day, so both read "ends Wednesday".
        _end = State(initialValue: item.isAllDay
                     ? AllDayDate.localDay(of: AllDayDate.utc.date(byAdding: .day, value: -1, to: item.end) ?? item.end,
                                           calendar: .current)
                     : item.end)
        _descriptionText = State(initialValue: item.notes ?? "")
        _selectedSpaceName = State(initialValue: item.spaceName)
        _noteID = State(initialValue: item.noteID)
    }

    // MARK: - Mode (from the item's own flags)

    private var isWorkBlock: Bool { item.isWorkBlock || state.tasks.contains { $0.id == item.id } }
    private var isReadOnly: Bool { item.isReadOnly }
    /// The pattern this session belongs to, for the badge and the scope dialogs. Nil for
    /// a one-off (and for an external `isRecurring` instance, whose series lives in
    /// Google and stays read-only here).
    private var seriesRule: RecurrenceRule? {
        item.recurrenceRule.flatMap(RecurrenceRule.init(rruleText:))
    }
    /// True when this is one session of an Atlas-owned repeating series — the only case
    /// where "this / this and following / all" is a real question.
    private var isSeriesMember: Bool { !isReadOnly && !isWorkBlock && item.isSeriesMember }
    /// Work-block whose backing task is a Canvas assignment — Canvas owns the title
    /// (re-sync overwrites it), so the title locks while scheduling stays fully editable.
    private var isCanvasBackedBlock: Bool {
        guard isWorkBlock, let task = state.tasks.first(where: { $0.id == item.id }) else { return false }
        // A generic-ICS-origin task (feedType "ics") is never Canvas, even if it carries a UID.
        return task.canvasUID != nil && task.feedType != "ics"
    }
    /// Note-linking has a durable home only for Atlas events + work-blocks (external events
    /// are rebuilt every sync and never persisted).
    private var canLinkNote: Bool { !isReadOnly && (isWorkBlock || item.source == .atlas) }
    /// References attach to `events(id)`, so only a persisted Atlas event qualifies —
    /// external items are rebuilt each sync (unstable ids) and a work-block's id lives
    /// in `tasks`, not `events` (manage those on the task's detail page).
    private var canAttachReferences: Bool { !isReadOnly && !isWorkBlock && item.source == .atlas }
    /// Space is a property of the `events` row (or its Google/Apple mirror), so only a
    /// writable event can move between spaces. A work-block's space lives on its backing
    /// task (manage it on the task's detail page), and read-only feed items are locked.
    private var canEditSpace: Bool { !isReadOnly && !isWorkBlock }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                duplicateSourceNote
                // A Canvas item whose course has no class yet — never dropped, never
                // blocking; picking here teaches the mapping for good.
                if let course = item.canvasCourse, item.projectID == nil {
                    UnassignedClassChip(course: course)
                }
                if isReadOnly || isCanvasBackedBlock { lockBanner }
                fields
                if canLinkNote { linkedNoteSection }
                if canAttachReferences { referencesSection }
                footer
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(28)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onChange(of: start) { oldStart, newStart in
            // Moving to another day carries a multi-day span along, then the end is clamped:
            // an all-day end is inclusive (ending on the start day is a one-day event), a
            // timed one needs a real length.
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: oldStart),
                                          to: cal.startOfDay(for: newStart)).day ?? 0
            if days != 0 { end = cal.date(byAdding: .day, value: days, to: end) ?? end }
            if item.isAllDay {
                if end < newStart { end = newStart }
            } else if end <= newStart {
                end = cal.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
                .frame(width: 560, height: 540)
                .background(AtlasTheme.Colors.bgDeep)
        }
        .sheet(isPresented: $showRefPicker, onDismiss: syncEventAttachments) {
            AttachReferencePicker(projectID: item.projectID, selection: $referenceSelection)
        }
        // Scope prompts. Editing or deleting ONE session of a series is ambiguous —
        // cancelling next Tuesday and cancelling the whole thing look identical until
        // asked — so nothing is written until the user says how far it reaches.
        .confirmationDialog("Change repeating event",
                            isPresented: Binding(get: { pendingSeriesEdit != nil },
                                                 set: { if !$0 { pendingSeriesEdit = nil } })) {
            ForEach(SeriesScope.allCases, id: \.self) { scope in
                Button(scope.label) {
                    guard let edited = pendingSeriesEdit else { return }
                    pendingSeriesEdit = nil
                    state.updateSeries(edited, scope: scope)
                    close()
                }
            }
            Button("Cancel", role: .cancel) { pendingSeriesEdit = nil }
        } message: {
            Text(seriesRule?.summary ?? "This event repeats.")
        }
        .confirmationDialog("Delete repeating event", isPresented: $confirmingSeriesDelete) {
            ForEach(SeriesScope.allCases, id: \.self) { scope in
                Button(scope.label, role: .destructive) {
                    state.deleteSeries(item, scope: scope)
                    close()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(seriesRule?.summary ?? "This event repeats.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: close) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").atlasFont(size: 12, weight: .semibold)
                        Text("Back").atlasFont(size: 13, weight: .medium, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                if isSeriesMember, let rule = seriesRule {
                    atlasTag(text: rule.summary, color: AtlasTheme.Colors.textMuted)
                }
                examBadge
                sourceBadge
            }
            if isReadOnly || isCanvasBackedBlock {
                Text(title)
                    .atlasFont(size: 29, weight: .bold, design: .rounded)
                    .tracking(-0.4)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            } else {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 29, weight: .bold, design: .rounded)
                    .tracking(-0.4)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .tint(AtlasTheme.Colors.accent)
            }
        }
    }

    /// The other calendars this same block also lives on — copies collapsed behind this one
    /// by display-time dedup, so the user knows the duplicate wasn't lost. Every label is the
    /// hidden copy's OWN ingest-stamped source; nothing here is inferred.
    @ViewBuilder private var duplicateSourceNote: some View {
        if !item.duplicateSources.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "square.on.square").atlasFont(size: 11)
                Text("Also in \(item.duplicateSources.map(\.displayName).joined(separator: ", "))")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// "EXAM" when the title reads like one — the same rule the `.ics` import sorts by
    /// (`ICSFile.isExamTitle`), so a final looks like a final wherever it came from.
    @ViewBuilder private var examBadge: some View {
        if ICSFile.isExamTitle(item.title) {
            atlasTag(text: "Exam", color: AtlasTheme.Colors.danger)
        }
    }

    private var sourceBadge: some View {
        let label: String
        let color: Color
        if isReadOnly && item.isRecurring {
            label = "Recurring · \(item.source.displayName)"; color = AtlasTheme.Colors.textMuted
        } else if isWorkBlock {
            label = "Planned work"; color = AtlasTheme.Colors.accentText
        } else {
            label = item.source.displayName
            color = item.source == .atlas ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.school
        }
        return atlasTag(text: label, color: color)
    }

    private var lockBanner: some View {
        let msg: String
        if item.source == .canvas || isCanvasBackedBlock {
            msg = "From Canvas — synced automatically. Schedule it; title and dates update from your feed."
        } else if item.isRecurring {
            msg = "Recurring event — edit the series in \(item.source.displayName)."
        } else {
            msg = "From \(item.source.displayName) — shown, not editable."
        }
        return HStack(spacing: 8) {
            Image(systemName: "lock.fill").atlasFont(size: 12)
            Text(msg).atlasFont(size: 13, design: .rounded)
        }
        .foregroundStyle(AtlasTheme.Colors.textMuted)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasHairlineBelow()
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldGroup("STARTS") {
                if isReadOnly {
                    readOnlyDate(start)
                } else {
                    AtlasDateField(date: $start, includesTime: !item.isAllDay)
                }
            }
            fieldGroup("ENDS") {
                if isReadOnly {
                    readOnlyDate(end)
                } else {
                    // All-day picks the LAST day covered (inclusive); `save()` stores the
                    // exclusive end the canonical encoding wants.
                    AtlasDateField(date: $end, includesTime: !item.isAllDay, minDate: start)
                }
            }
            if canEditSpace {
                fieldGroup("SPACE") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.calendarSpaceColor(named: selectedSpaceName))
                            .frame(width: 9, height: 9)
                        Picker("Space", selection: $selectedSpaceName) {
                            ForEach(state.spaces) { space in
                                Text(space.name).tag(space.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            fieldGroup("DESCRIPTION") {
                if isReadOnly {
                    Text(descriptionText.isEmpty ? "—" : descriptionText)
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextEditor(text: $descriptionText)
                        .atlasFont(size: 14, design: .rounded)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .tint(AtlasTheme.Colors.accent)
                }
            }
            if !isReadOnly {
                Button(action: save) {
                    Text("Save")
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                                .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                        )
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Linked note

    private var linkedNoteSection: some View {
        fieldGroup("LINKED NOTE") {
            HStack(spacing: 8) {
                Menu {
                    Button("None") { noteID = nil }
                    Divider()
                    ForEach(state.notes) { note in
                        Button(note.title) { noteID = note.id }
                    }
                    Divider()
                    Button("New note…") {
                        let n = state.addNote(title: title.isEmpty ? "Untitled note" : title)
                        noteID = n.id
                        editingNote = n
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").atlasFont(size: 12)
                        Text(linkedNoteTitle).atlasFont(size: 13, weight: .medium, design: .rounded)
                        Image(systemName: "chevron.down").atlasFont(size: 10)
                    }
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                .menuStyle(.borderlessButton)
                if noteID != nil {
                    Button { noteID = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .help("Clear the linked note")
                }
                Spacer()
            }
        }
    }

    private var linkedNoteTitle: String {
        if let id = noteID, let n = state.notes.first(where: { $0.id == id }) { return n.title }
        return "Tag a note…"
    }

    // MARK: - References

    private var referencesSection: some View {
        fieldGroup("REFERENCES") {
            VStack(alignment: .leading, spacing: 0) {
                let refs = state.references(forEvent: item.id)
                if refs.isEmpty {
                    Text("No references attached.")
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                } else {
                    ForEach(refs) { ref in
                        ReferenceListRow(reference: ref) {
                            state.detachReference(ref.id, fromEvent: item.id)
                        }
                    }
                }
                Button {
                    referenceSelection = Set(state.references(forEvent: item.id).map(\.id))
                    showRefPicker = true
                } label: {
                    Label("Add reference", systemImage: "plus")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .padding(.top, refs.isEmpty ? 0 : 10)
            }
        }
    }

    /// Applies the picker's selection to the event's attachments (diff → attach/detach).
    private func syncEventAttachments() {
        let current = Set(state.references(forEvent: item.id).map(\.id))
        for added in referenceSelection.subtracting(current) {
            state.attachReference(added, toEvent: item.id)
        }
        for removed in current.subtracting(referenceSelection) {
            state.detachReference(removed, fromEvent: item.id)
        }
    }

    // MARK: - Footer actions

    private var footer: some View {
        HStack(spacing: 16) {
            if !isReadOnly {
                Button(action: deleteOrUnschedule) {
                    Label(isWorkBlock ? "Unschedule" : "Delete",
                          systemImage: isWorkBlock ? "tray.and.arrow.down" : "trash")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.danger)
            }
            if let pid = item.projectID, state.project(pid) != nil {
                Button { state.calendarDetailItem = nil; state.route = .project(pid) } label: {
                    Label("Open Project", systemImage: "folder").atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            if let nid = noteID, let n = state.notes.first(where: { $0.id == nid }) {
                Button { openNote(n) } label: {
                    Label("Open Note", systemImage: "arrow.up.right.square").atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    /// Read-only date/time as plain editorial mono text — no input chrome, so a
    /// synced Canvas/external item reads as typography on paper, not a disabled box.
    private func readOnlyDate(_ date: Date) -> some View {
        let f = DateFormatter()
        f.dateFormat = item.isAllDay ? "EEE, MMM d" : "EEE, MMM d · h:mm a"
        return Text(f.string(from: date))
            .atlasMono(size: 14)
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(_ label: String,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).atlasCapsLabel()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasHairlineBelow()
    }

    private func close() {
        state.calendarDetailItem = nil
        state.route = .calendar
    }

    private func save() {
        // All-day: re-anchor the picked local dates to canonical UTC midnight (`AllDayDate`).
        // The ENDS field holds the INCLUSIVE last day, so the stored end is the day after it.
        let finalStart: Date
        let finalEnd: Date
        if item.isAllDay {
            finalStart = AllDayDate.anchor(forDayOf: start, in: .current)
            let lastDay = AllDayDate.anchor(forDayOf: max(end, start), in: .current)
            finalEnd = AllDayDate.utc.date(byAdding: .day, value: 1, to: lastDay) ?? finalStart
        } else {
            finalStart = start
            finalEnd = end > start ? end : start.addingTimeInterval(3600)
        }
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : descriptionText

        if isWorkBlock {
            let dur = max(1, Int(finalEnd.timeIntervalSince(start) / 60))
            state.updateScheduledTask(id: item.id, title: title, start: start,
                                      durationMin: dur, notes: desc, noteID: noteID)
        } else {
            var updated = item
            updated.title = title
            updated.start = finalStart
            updated.end = finalEnd
            updated.notes = desc
            updated.noteID = noteID
            // Move between spaces — recolor and re-resolve the space id so `updateEvent`
            // can re-route the event (and its Google/Apple mirror) to the new connection.
            updated.spaceName = selectedSpaceName
            updated.color = state.calendarSpaceColor(named: selectedSpaceName)
            updated.spaceID = state.spaceID(named: selectedSpaceName)
            if isSeriesMember {
                // Park it — the dialog's choice calls `updateSeries` and closes.
                pendingSeriesEdit = updated
                return
            }
            state.updateEvent(updated)
        }
        close()
    }

    private func deleteOrUnschedule() {
        if isWorkBlock {
            state.unscheduleTask(id: item.id)
        } else if isSeriesMember {
            confirmingSeriesDelete = true   // the dialog's choice deletes and closes
            return
        } else {
            state.deleteEvent(id: item.id)
        }
        close()
    }

    private func openNote(_ note: Note) {
        if let pid = note.projectID, state.project(pid) != nil {
            state.calendarDetailItem = nil
            state.route = .project(pid)
        } else {
            editingNote = note   // loose note → open its editor directly
        }
    }
}
