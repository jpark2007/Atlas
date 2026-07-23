import SwiftUI
import AtlasCore

// MARK: - Capture apply seam
//
// One place that turns a decoded `CaptureResult` into the right domain object.
// Extracted from CaptureOverlay so it is unit-testable and reused for EVERY item
// in a multi-item capture (the array returned by `AtlasAI.parse`).

extension AppState {
    /// Create the task / event / note described by `result` and return the
    /// user-facing outcome plus a snapshot of the created item (for capture
    /// history / undo). Never throws — an event missing a start time, or an
    /// unrecognized kind, degrades to a plain task so capture never loses data.
    @discardableResult
    func applyCapture(_ result: CaptureResult) -> AppliedCapture {
        switch result.kind {
        case "event":
            return applyEvent(result)

        case "note":
            let note = addNote(title: result.title,
                               body: result.notes ?? "",
                               spaceName: result.spaceName,
                               isExternal: false)
            return AppliedCapture(outcome: .note, item: CaptureHistoryItem(note: note))

        case "task":
            let due = CaptureDateParser.date(from: result.dueISO)
            let task = addTask(title: result.title,
                               dueDate: due,
                               durationMin: result.durationMin,
                               spaceName: result.spaceName,
                               projectName: result.projectName ?? "")
            return AppliedCapture(outcome: .task(hasDate: due != nil),
                                  item: CaptureHistoryItem(task: task))

        default:
            // Unknown kind — keep the parsed title, save as a plain task.
            let task = addTask(title: result.title)
            return AppliedCapture(outcome: .task(hasDate: false),
                                  item: CaptureHistoryItem(task: task))
        }
    }

    /// Place an event on the calendar. Without a parseable `startISO` there's no
    /// slot to place it in, so it falls back to a dated/undated task.
    ///
    /// End time: an explicit `endISO` after the start wins; otherwise the event
    /// runs `durationMin` (default 60). An `isAllDay` event spans one calendar day
    /// — midnight → next midnight — matching EventEditorSheet's convention.
    /// Source stays the `.atlas` default (rule 5 — never mislabel origin).
    private func applyEvent(_ result: CaptureResult) -> AppliedCapture {
        guard let start = CaptureDateParser.date(from: result.startISO) else {
            let task = addTask(title: result.title)
            return AppliedCapture(outcome: .task(hasDate: false),
                                  item: CaptureHistoryItem(task: task))
        }

        let isAllDay = result.isAllDay ?? false
        let eventStart: Date
        let eventEnd: Date
        if isAllDay {
            let cal = Calendar.current
            eventStart = cal.startOfDay(for: start)
            eventEnd = cal.date(byAdding: .day, value: 1, to: eventStart) ?? eventStart
        } else {
            eventStart = start
            if let end = CaptureDateParser.date(from: result.endISO), end > start {
                eventEnd = end
            } else {
                eventEnd = start.addingTimeInterval(Double(result.durationMin ?? 60) * 60)
            }
        }

        var event = CalendarEvent(
            title: result.title,
            subtitle: "",
            start: eventStart,
            end: eventEnd,
            color: calendarSpaceColor(named: result.spaceName),
            spaceName: result.spaceName,
            isAllDay: isAllDay
        )
        event.spaceID = spaceID(named: result.spaceName)
        addEvent(event)
        return AppliedCapture(outcome: .event, item: CaptureHistoryItem(event: event))
    }

    /// Create a plain task carrying `notes` — used by the quick-capture
    /// graceful fallback so a long pasted dump keeps its full text in the body
    /// (never a giant title). Mirrors `addTask` but persists a notes field.
    @discardableResult
    func addTask(title: String, notes: String) -> TaskItem {
        let resolvedSpace = resolvedTaskSpaceName(hint: "", text: title)
        var task = TaskItem(title: title,
                            dueLabel: TaskItem.dueLabel(for: nil),
                            notes: notes)
        task.spaceName = resolvedSpace
        task.spaceID = spaceID(named: resolvedSpace)
        task.spaceColor = calendarSpaceColor(named: resolvedSpace)
        tasks.append(task)
        Task { try? await self.db?.upsertTask(task) }
        return task
    }
}
