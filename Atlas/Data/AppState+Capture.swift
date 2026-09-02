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
            return applyTask(result)

        case "update":
            // The model says this refers to something the user already has.
            // A missing/unknown id degrades to a normal create, so a hallucinated
            // reference can never make the capture disappear.
            if case .update(let id) = CaptureAction.decide(result, knownIDs: Set(tasks.map(\.id))),
               let updated = applyUpdate(result, taskID: id) {
                return updated
            }
            return applyTask(result)

        default:
            // Unknown kind — keep the parsed title, save as a plain task.
            let task = addTask(title: result.title)
            return AppliedCapture(outcome: .task(hasDate: false),
                                  item: CaptureHistoryItem(task: task))
        }
    }

    /// The project (class) `result` names, looked up inside the space the item
    /// actually lands in. Matched case-insensitively so a model answering
    /// "general chemistry" still lands on the real class. Nil when the capture
    /// named no project, or one this space doesn't have — an unmatched name
    /// renders as unassigned anyway and loses the project color cascade, so it
    /// must never be stored as if it were real.
    private func captureProject(_ result: CaptureResult, in spaceName: String) -> Project? {
        let name = (result.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return spaces
            .first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }?
            .projects
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Create the task described by `result`.
    private func applyTask(_ result: CaptureResult) -> AppliedCapture {
        let due = CaptureDateParser.date(from: result.dueISO)
        // Resolve the space first: the project must be looked up in the space the
        // task really lands in, and `projectName` is only meaningful paired with it.
        let space = resolvedTaskSpaceName(hint: result.spaceName, text: result.title)
        let task = addTask(title: result.title,
                           dueDate: due,
                           durationMin: result.durationMin,
                           spaceName: space,
                           projectName: captureProject(result, in: space)?.name ?? "")
        return AppliedCapture(outcome: .task(hasDate: due != nil),
                              item: CaptureHistoryItem(task: task))
    }

    /// Attach the capture to an EXISTING task instead of duplicating it: a stated
    /// deadline moves the due date, stated detail is appended to the notes.
    /// Everything else about the task is left alone. The returned history item
    /// carries the pre-capture values so Undo restores rather than deletes.
    /// Returns nil when the task vanished between decode and apply.
    private func applyUpdate(_ result: CaptureResult, taskID: UUID) -> AppliedCapture? {
        guard let before = tasks.first(where: { $0.id == taskID }) else { return nil }
        let prior = CaptureHistoryItem.PriorTaskState(dueDate: before.dueDate,
                                                      notes: before.notes)

        if let due = CaptureDateParser.date(from: result.dueISO) {
            setDueDate(taskId: taskID, date: due)
        }
        let extra = (result.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty, !before.notes.contains(extra) {
            updateTaskNotes(taskId: taskID,
                            notes: before.notes.isEmpty ? extra : before.notes + "\n" + extra)
        }

        guard let after = tasks.first(where: { $0.id == taskID }) else { return nil }
        var item = CaptureHistoryItem(task: after)
        item.priorTask = prior
        return AppliedCapture(outcome: .updated, item: item)
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
        // A captured class session/lab keeps its class link, so it wears the
        // project's color in the grid and shows up under that class.
        event.projectID = captureProject(result, in: result.spaceName)?.id

        // Repeating? Expand it into real sessions. A rule the model garbled maps to nil,
        // and one that yields a single date isn't a series — both fall through to the
        // ordinary one-off path below rather than failing the capture.
        if let spec = result.recurrence,
           let rule = RecurrenceRule(capture: spec) {
            let starts = rule.occurrences(startingAt: eventStart)
            if starts.count > 1 {
                return applySeries(event, rule: rule, starts: starts,
                                   duration: eventEnd.timeIntervalSince(eventStart))
            }
        }

        addEvent(event)
        return AppliedCapture(outcome: .event, item: CaptureHistoryItem(event: event))
    }

    /// Materialize one repeating capture into its sessions.
    ///
    /// Every instance is a full copy of `template` on its own date, with its own id and a
    /// shared `seriesID`; each carries the rule's RRULE text so any single session can
    /// describe the whole series. `duration` is carried forward rather than re-derived so
    /// a 50-minute block stays 50 minutes on every date — and because `RecurrenceRule`
    /// re-applies the wall-clock start per day, a series crossing a DST change keeps its
    /// stated time. Written through `addEvents`, so the whole run is ONE Supabase upsert.
    ///
    /// A capture that lands on a CLASS whose `meetingPattern` already covers the same
    /// slot produces a session next to `SchoolCalendar`'s derived meeting; the two
    /// collapse at display time via `CalendarSync.collapsingDuplicates` (same title, same
    /// instant), so the grid shows one block, not two.
    private func applySeries(_ template: CalendarEvent,
                             rule: RecurrenceRule,
                             starts: [Date],
                             duration: TimeInterval) -> AppliedCapture {
        let seriesID = UUID()
        let rruleText = rule.rruleText
        let instances = starts.map { start -> CalendarEvent in
            var instance = template
            instance.id = UUID()
            instance.start = start
            instance.end = start.addingTimeInterval(duration)
            instance.seriesID = seriesID
            instance.recurrenceRule = rruleText
            return instance
        }
        addEvents(instances)
        let snapshots = instances.map(CaptureHistoryItem.init(event:))
        return AppliedCapture(outcome: .eventSeries(count: instances.count),
                              item: snapshots[0],
                              alsoCreated: Array(snapshots.dropFirst()))
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
