import SwiftUI

// MARK: - Capture apply seam
//
// One place that turns a decoded `CaptureResult` into the right domain object.
// Extracted from CaptureOverlay so it is unit-testable and reused for EVERY item
// in a multi-item capture (the array returned by `AtlasAI.parse`).

extension AppState {
    /// Create the task / event / note described by `result` and return the
    /// user-facing outcome. Never throws — an event missing a start time, or an
    /// unrecognized kind, degrades to a plain task so capture never loses data.
    @discardableResult
    func applyCapture(_ result: CaptureResult) -> CaptureOutcome {
        switch result.kind {
        case "event":
            return applyEvent(result)

        case "note":
            addNote(title: result.title,
                    body: result.notes ?? "",
                    spaceName: result.spaceName,
                    isExternal: false)
            return .note

        case "task":
            let due = CaptureDateParser.date(from: result.dueISO)
            addTask(title: result.title,
                    dueDate: due,
                    durationMin: result.durationMin)
            return .task(hasDate: due != nil)

        default:
            // Unknown kind — keep the parsed title, save as a plain task.
            addTask(title: result.title)
            return .task(hasDate: false)
        }
    }

    /// Place an event on the calendar. Without a parseable `startISO` there's no
    /// slot to place it in, so it falls back to a dated/undated task.
    private func applyEvent(_ result: CaptureResult) -> CaptureOutcome {
        guard let start = CaptureDateParser.date(from: result.startISO) else {
            addTask(title: result.title)
            return .task(hasDate: false)
        }
        let durationSeconds = Double(result.durationMin ?? 60) * 60
        let event = CalendarEvent(
            title: result.title,
            subtitle: "",
            start: start,
            end: start.addingTimeInterval(durationSeconds),
            color: calendarSpaceColor(named: result.spaceName),
            spaceName: result.spaceName
        )
        addEvent(event)
        return .event
    }
}
