import SwiftUI
import AtlasCore

/// The dashboard, restructured to the locked Phase-3 mockup (spec 3.1):
/// a tiny mono greeting/date title bar, then a two-column body — a main column
/// (live clock · today's focus · recent notes) beside a right rail (an outlined
/// mini-month date navigator · the selected day's agenda).
///
/// The rail (navigator + agenda, its own `selectedDay`/`visibleMonth`) lives in
/// `MiniMonthAgenda`, shared with the menu-bar calendar popup. The focus list is
/// always the next upcoming OPEN tasks by deadline, NEVER the rail's selected
/// day (a fixed glance at what's next, per the binding data semantics).
struct DashboardView: View {
    @EnvironmentObject var state: AppState

    /// The note open in the corner-card editor (nil = closed) — same host idiom
    /// as ProjectDetailView: an overlay, not a modal sheet.
    @State private var editingNote: Note?

    /// How many upcoming tasks the focus list shows.
    private let focusCount = 8
    /// How many recent notes the notes section shows.
    private let noteCount = 5

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                titleBar

                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 26) {
                        clockBlock
                        focusList
                        recentNotes
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    MiniMonthAgenda(onOpenCalendar: { state.route = .calendar })
                        .frame(width: 348)
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
        // Corner-card editor (not a modal sheet) — the dashboard stays visible
        // behind it; drag-resize and expand live in `NoteCardOverlay`.
        .overlay(alignment: .bottomTrailing) {
            if let note = editingNote {
                NoteCardOverlay(note: note) { editingNote = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: editingNote?.id)
    }

    // MARK: - Title bar (tiny mono greeting left · date right)

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(greeting)
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.4)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Spacer()
            Text(titleDate)
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.4)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// Time-of-day greeting, uppercased ("GOOD AFTERNOON"), driven by `state.now`.
    private var greeting: String {
        switch calendar.component(.hour, from: state.now) {
        case 5..<12:  return "GOOD MORNING"
        case 12..<17: return "GOOD AFTERNOON"
        default:      return "GOOD EVENING"
        }
    }

    /// "MON — JUL 6, 2026" — driven by `state.now`.
    private var titleDate: String {
        "\(DashFmt.weekdayShort.string(from: state.now)) — \(DashFmt.monthDayYear.string(from: state.now))"
            .uppercased()
    }

    // MARK: - Clock block (live 12-hour clock + dateline, plain on paper)

    /// Huge mono ink digits, clay colons, muted seconds, small AM/PM; a mono
    /// dateline below; a hairline under the whole block. No panel, no boxes, no
    /// flip animation. `TimelineView` ticks it once a second.
    private var clockBlock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                clockDigits(context.date)
                Text(dateline(context.date))
                    .atlasMono(size: 12, weight: .medium)
                    .tracking(1.6)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .atlasHairlineBelow()
        }
    }

    private func clockDigits(_ date: Date) -> some View {
        let h24 = calendar.component(.hour, from: date)
        let h = h24 % 12 == 0 ? 12 : h24 % 12
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let ampm = h24 < 12 ? "AM" : "PM"
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            bigDigit("\(h)")
            bigColon
            bigDigit(String(format: "%02d", m))
            Text(":")
                .atlasMono(size: 26, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.accent)
                .padding(.leading, 4)
            Text(String(format: "%02d", s))
                .atlasMono(size: 26, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(ampm)
                .atlasMono(size: 15, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.leading, 8)
        }
    }

    private func bigDigit(_ s: String) -> some View {
        Text(s)
            .atlasMono(size: 64, weight: .semibold)
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
    }

    private var bigColon: some View {
        Text(":")
            .atlasMono(size: 64, weight: .semibold)
            .foregroundStyle(AtlasTheme.Colors.accent)
    }

    /// "MONDAY —— JUL 6 / 2026".
    private func dateline(_ date: Date) -> String {
        let day = DashFmt.weekdayFull.string(from: date).uppercased()
        let md  = DashFmt.monthDay.string(from: date).uppercased()
        let yr  = DashFmt.year.string(from: date)
        return "\(day) —— \(md) / \(yr)"
    }

    // MARK: - Focus list (next upcoming open tasks — NOT the selected day)

    private var focusList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S FOCUS").atlasCapsLabel()

            let tasks = focusTasks
            if tasks.isEmpty {
                Text("Nothing due — you're clear.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tasks) { task in focusRow(task) }
                }
            }

            addTaskAffordance
        }
    }

    /// The next `focusCount` OPEN tasks ordered by deadline: dated before undated,
    /// earliest `dueDate` first, `scheduledAt` as the tiebreaker. Independent of
    /// the calendar selection (a fixed "what's next" glance).
    private var focusTasks: [TaskItem] {
        // Just-checked tasks linger (struck-through) before sliding out.
        let open = state.tasks.filter(state.isVisiblyPending)
        let sorted = open.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?):
                if da != db { return da < db }
                return (a.scheduledAt ?? .distantFuture) < (b.scheduledAt ?? .distantFuture)
            case (_?, nil): return true       // dated tasks come before undated
            case (nil, _?): return false
            case (nil, nil):
                return (a.scheduledAt ?? .distantFuture) < (b.scheduledAt ?? .distantFuture)
            }
        }
        return Array(sorted.prefix(focusCount))
    }

    private func focusRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { state.toggleTask(task.id) }
            } label: {
                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                    .atlasFont(size: 15)
                    .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)

            Button { state.route = .task(task.id) } label: {
                HStack(spacing: 8) {
                    Text(task.title)
                        .atlasFont(size: 14, design: .rounded)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !task.dueLabel.isEmpty {
                        Text(task.dueLabel)
                            .atlasMono(size: 11, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                    if !task.spaceName.isEmpty {
                        atlasTag(text: task.spaceName, color: task.spaceColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    /// Plain text affordance (not a boxed input) — opens the existing quick capture.
    private var addTaskAffordance: some View {
        Button { state.presentCapture = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
                Text("Add a task")
                    .atlasFont(size: 13, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: - Recent notes (plain rows, corner-card open)

    private var recentNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT NOTES").atlasCapsLabel()

            let notes = recentNotesList
            if notes.isEmpty {
                Text("No notes yet.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        noteRow(note)
                        if index < notes.count - 1 {
                            Divider().overlay(AtlasTheme.Colors.hairline)
                        }
                    }
                }
            }
        }
    }

    private var recentNotesList: [Note] {
        Array(state.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(noteCount))
    }

    private func noteRow(_ note: Note) -> some View {
        Button { editingNote = note } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(note.title.isEmpty ? "Untitled note" : note.title)
                            .atlasTitleSerif(size: 15)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .lineLimit(1)
                        if isLinkedDoc(note) {
                            atlasTag(text: "Google Doc", color: AtlasTheme.Colors.accentText)
                        }
                    }
                    Text(noteMeta(note))
                        .atlasMono(size: 11, weight: .regular)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A note is a linked Doc-note when a `.docNote` reference points back at it
    /// (mirrors `NotesListView.isLinkedDoc`).
    private func isLinkedDoc(_ note: Note) -> Bool {
        state.references.contains { $0.kind == .docNote && $0.noteID == note.id }
    }

    /// "JUL 5 · SCHOOL" — date, then space when the note has one.
    private func noteMeta(_ note: Note) -> String {
        let date = DashFmt.monthDay.string(from: note.updatedAt).uppercased()
        if let space = note.spaceName, !space.isEmpty {
            return "\(date) · \(space.uppercased())"
        }
        return date
    }

}

// MARK: - Cached formatters

/// Cached `DateFormatter`s for the dashboard's mono datelines. Strings that mix
/// em-dashes / slashes are composed in code from these plain patterns so no
/// literal-quoting is needed.
private enum DashFmt {
    static let weekdayShort  = formatter("EEE")
    static let weekdayFull   = formatter("EEEE")
    static let monthDay      = formatter("MMM d")
    static let monthDayYear  = formatter("MMM d, yyyy")
    static let year          = formatter("yyyy")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}
