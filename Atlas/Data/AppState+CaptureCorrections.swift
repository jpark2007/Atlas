import Foundation
import AtlasCore

// MARK: - Chip corrections on a COMMITTED capture (Phase 4 §3)
//
// Capture commits on Enter — no review screen. The result cards that stay on
// screen fix the committed item IN PLACE through the app's normal mutation
// paths, and keep the capture-history snapshot in step so per-item Undo still
// knows what it made.

/// What the Type chip can turn a captured item into. "Deadline" is not a fourth
/// storage kind — it is a task that carries a due date, which is exactly how the
/// rest of Atlas draws deadlines.
enum CaptureItemType: String, CaseIterable, Identifiable {
    case task, deadline, event, note
    var id: String { rawValue }

    var label: String {
        switch self {
        case .task:     return "Task"
        case .deadline: return "Deadline"
        case .event:    return "Event"
        case .note:     return "Note"
        }
    }

    /// How a committed item currently reads: a dated task IS a deadline.
    static func of(_ item: CaptureHistoryItem) -> CaptureItemType {
        switch item.kind {
        case .event: return .event
        case .note:  return .note
        case .task:  return item.dueDate == nil ? .task : .deadline
        }
    }
}

extension AppState {

    // MARK: Class ▾

    /// Re-file a committed item into `spaceName` (and optionally a project/class
    /// inside it). Returns the refreshed snapshot, or nil if the item is gone.
    func recaptureSpace(_ item: CaptureHistoryItem,
                        spaceName: String,
                        projectName: String) -> CaptureHistoryItem? {
        switch item.kind {
        case .task:
            setTaskSpace(taskId: item.id, spaceName: spaceName)
            setTaskProject(taskId: item.id, projectName: projectName)
        case .event:
            guard var event = events.first(where: { $0.id == item.id }) else { return nil }
            event.spaceName = spaceName
            event.spaceID = spaceID(named: spaceName)
            event.color = calendarSpaceColor(named: spaceName)
            updateEvent(event)
        case .note:
            guard var note = notes.first(where: { $0.id == item.id }) else { return nil }
            note.spaceName = spaceName
            note.spaceID = spaceID(named: spaceName)
            updateNote(note)
        }
        return snapshot(of: item)
    }

    // MARK: Due ▾

    /// Set (or clear) a committed item's date. A task's due date moves directly;
    /// an event keeps its time of day and moves to that calendar day, because a
    /// stated time is sacred. `nil` clears a task's due date; an event always has
    /// a slot, so clearing is not offered for one.
    func recaptureDue(_ item: CaptureHistoryItem, date: Date?) -> CaptureHistoryItem? {
        switch item.kind {
        case .task:
            setDueDate(taskId: item.id, date: date)
        case .event:
            guard let date, var event = events.first(where: { $0.id == item.id }) else { return nil }
            let cal = Calendar.current
            let length = event.end.timeIntervalSince(event.start)
            let time = cal.dateComponents([.hour, .minute], from: event.start)
            let moved = cal.date(bySettingHour: time.hour ?? 0,
                                 minute: time.minute ?? 0,
                                 second: 0,
                                 of: cal.startOfDay(for: date)) ?? date
            event.start = moved
            event.end = moved.addingTimeInterval(length)
            updateEvent(event)
        case .note:
            return nil          // a note has no date — the chip is inert
        }
        return snapshot(of: item)
    }

    // MARK: Type ▾

    /// Turn a committed item into a different kind. There is no in-place
    /// conversion in the data model, so this deletes the old object and creates
    /// the new one from the same title / space / date / notes, returning the NEW
    /// snapshot (a different id) for the card and the history entry.
    ///
    /// Refuses to run on an item capture only UPDATED (`priorTask != nil`) —
    /// converting would delete something the user already had.
    func recaptureType(_ item: CaptureHistoryItem, to type: CaptureItemType) -> CaptureHistoryItem? {
        guard item.priorTask == nil, CaptureItemType.of(item) != type else { return nil }
        guard let carried = carriedFields(of: item) else { return nil }

        switch item.kind {
        case .task:  deleteTask(id: item.id)
        case .event: deleteEvent(id: item.id)
        case .note:  deleteNote(id: item.id)
        }

        switch type {
        case .task:
            return CaptureHistoryItem(task: addTask(title: carried.title,
                                                    spaceName: carried.spaceName,
                                                    projectName: carried.projectName))
        case .deadline:
            let due = carried.date ?? Calendar.current.startOfDay(for: Date())
            return CaptureHistoryItem(task: addTask(title: carried.title,
                                                    dueDate: due,
                                                    spaceName: carried.spaceName,
                                                    projectName: carried.projectName))
        case .event:
            let start = carried.date ?? Date()
            var event = CalendarEvent(title: carried.title,
                                      subtitle: "",
                                      start: start,
                                      end: start.addingTimeInterval(3600),
                                      color: calendarSpaceColor(named: carried.spaceName),
                                      spaceName: carried.spaceName,
                                      notes: carried.notes.isEmpty ? nil : carried.notes)
            event.spaceID = spaceID(named: carried.spaceName)
            addEvent(event)
            return CaptureHistoryItem(event: event)
        case .note:
            return CaptureHistoryItem(note: addNote(title: carried.title,
                                                    body: carried.notes,
                                                    spaceName: carried.spaceName,
                                                    isExternal: false))
        }
    }

    // MARK: - Helpers

    private struct CarriedFields {
        let title: String
        let spaceName: String
        let projectName: String
        let date: Date?
        let notes: String
    }

    /// The user-meaningful fields to carry across a type conversion, read from the
    /// LIVE object (the snapshot may be stale after an earlier chip edit).
    private func carriedFields(of item: CaptureHistoryItem) -> CarriedFields? {
        switch item.kind {
        case .task:
            guard let t = tasks.first(where: { $0.id == item.id }) else { return nil }
            return CarriedFields(title: t.title, spaceName: t.spaceName,
                                 projectName: t.projectName, date: t.dueDate, notes: t.notes)
        case .event:
            guard let e = events.first(where: { $0.id == item.id }) else { return nil }
            return CarriedFields(title: e.title, spaceName: e.spaceName,
                                 projectName: "", date: e.start, notes: e.notes ?? "")
        case .note:
            guard let n = notes.first(where: { $0.id == item.id }) else { return nil }
            return CarriedFields(title: n.title, spaceName: n.spaceName ?? "",
                                 projectName: "", date: nil, notes: n.body)
        }
    }

    /// Re-read the live object into a fresh history snapshot, preserving the
    /// update marker so Undo keeps restoring instead of deleting.
    private func snapshot(of item: CaptureHistoryItem) -> CaptureHistoryItem? {
        var fresh: CaptureHistoryItem
        switch item.kind {
        case .task:
            guard let t = tasks.first(where: { $0.id == item.id }) else { return nil }
            fresh = CaptureHistoryItem(task: t)
        case .event:
            guard let e = events.first(where: { $0.id == item.id }) else { return nil }
            fresh = CaptureHistoryItem(event: e)
        case .note:
            guard let n = notes.first(where: { $0.id == item.id }) else { return nil }
            fresh = CaptureHistoryItem(note: n)
        }
        fresh.priorTask = item.priorTask
        return fresh
    }

    // MARK: - Keeping capture history in step

    /// Swap one item inside a recorded capture for its corrected version, so the
    /// entry's Undo still targets the right object.
    func replaceCapturedItem(_ old: CaptureHistoryItem,
                             with new: CaptureHistoryItem,
                             inEntry entryID: UUID) {
        guard let e = captureHistory.firstIndex(where: { $0.id == entryID }),
              let i = captureHistory[e].items.firstIndex(where: { $0.id == old.id }) else { return }
        captureHistory[e].items[i] = new
        persistCaptureHistoryIfPossible()
    }

    /// Per-item Undo: revert just this item and drop it from its capture entry.
    func undoCapturedItem(_ item: CaptureHistoryItem, inEntry entryID: UUID) {
        // One chip stands for a whole repeating series, so undoing it takes back every
        // session — reverting only the representative would leave the rest stranded on
        // the calendar with no chip left to remove them.
        var reverted: Set<UUID> = [item.id]
        if item.kind == .event,
           let event = events.first(where: { $0.id == item.id }),
           let sid = event.seriesID {
            reverted = Set(events.filter { $0.seriesID == sid }.map(\.id))
            deleteSeries(event, scope: .allEvents)
        } else {
            revert(item)
        }
        guard let e = captureHistory.firstIndex(where: { $0.id == entryID }) else { return }
        captureHistory[e].items.removeAll { reverted.contains($0.id) }
        if captureHistory[e].items.isEmpty { captureHistory[e].undoneAt = Date() }
        persistCaptureHistoryIfPossible()
    }

    private func persistCaptureHistoryIfPossible() {
        guard let userID = loadedUserID else { return }
        CaptureHistoryStore.save(captureHistory, userID: userID)
    }
}
