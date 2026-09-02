import XCTest
@testable import AtlasCore
@testable import Atlas

@MainActor
final class AppStateCaptureTests: XCTestCase {
    func testAddTaskWithDueDateSetsDateAndLabel() {
        let state = AppState()
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let before = state.tasks.count
        let t = state.addTask(title: "Finish pset", dueDate: due, durationMin: 45)
        XCTAssertEqual(state.tasks.count, before + 1)
        XCTAssertEqual(t.dueDate, due)
        XCTAssertEqual(t.durationMin, 45)
        XCTAssertEqual(t.dueLabel, TaskItem.dueLabel(for: due))
        XCTAssertEqual(state.tasks.last?.dueDate, due)
    }

    func testAddTaskTitleOnlyStillWorks() {
        let state = AppState()
        let t = state.addTask(title: "Loose task")
        XCTAssertNil(t.dueDate)
        XCTAssertEqual(t.dueLabel, "")
    }

    // MARK: - applyCapture seam (WS-2)

    private func result(kind: String,
                        title: String,
                        space: String = "Personal",
                        dueISO: String? = nil,
                        startISO: String? = nil,
                        durationMin: Int? = nil,
                        notes: String? = nil,
                        endISO: String? = nil,
                        recurrence: CaptureRecurrence? = nil) -> CaptureResult {
        CaptureResult(kind: kind, title: title, spaceName: space,
                      projectName: nil, dueISO: dueISO, startISO: startISO,
                      endISO: endISO, durationMin: durationMin, isAllDay: nil,
                      notes: notes, recurrence: recurrence)
    }

    // MARK: - Repeating events

    /// One capture line becomes a real session per occurrence, all in one series.
    func testApplyCaptureRepeatingEventExpandsIntoASeries() throws {
        let state = AppState()
        let before = state.events.count
        let applied = state.applyCapture(
            result(kind: "event", title: "Yoga", space: "Health",
                   startISO: "2026-09-02T17:00:00Z",
                   endISO: "2026-09-02T17:50:00Z",
                   recurrence: CaptureRecurrence(freq: "weekly",
                                                 byDay: ["MO", "WE", "FR"],
                                                 untilISO: "2026-12-12")))

        let added = state.events.count - before
        XCTAssertGreaterThan(added, 30, "a full run of MWF sessions")
        XCTAssertEqual(applied.outcome, .eventSeries(count: added))
        // Undo has to be able to take back every session, not just the first.
        XCTAssertEqual(applied.items.count, added)
        XCTAssertEqual(applied.item.id, applied.items[0].id, "the chip points at the first")

        let sessions = state.events.suffix(added)
        XCTAssertEqual(Set(sessions.compactMap(\.seriesID)).count, 1, "one shared series id")
        XCTAssertEqual(Set(sessions.map(\.id)).count, added, "each session its own id")
        for session in sessions {
            XCTAssertEqual(session.title, "Yoga")
            XCTAssertEqual(session.recurrenceRule, "FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261212")
            XCTAssertEqual(session.end.timeIntervalSince(session.start), 50 * 60, accuracy: 0.5)
        }
    }

    /// A recurrence the model garbled must not corrupt the capture — it degrades to the
    /// plain one-off event it would have been without the pattern.
    func testUnusableRecurrenceStillCreatesASingleEvent() {
        let state = AppState()
        let before = state.events.count
        let applied = state.applyCapture(
            result(kind: "event", title: "Gym", space: "Health",
                   startISO: "2026-06-28T15:00:00Z", durationMin: 45,
                   recurrence: CaptureRecurrence(freq: "fortnightly")))
        XCTAssertEqual(applied.outcome, .event)
        XCTAssertEqual(state.events.count, before + 1)
        XCTAssertNil(state.events.last?.seriesID)
    }

    // MARK: - Series scope

    func testDeleteSeriesScopes() throws {
        let state = AppState()
        state.applyCapture(
            result(kind: "event", title: "Standup", space: "Work",
                   startISO: "2026-09-07T17:00:00Z", durationMin: 60,
                   recurrence: CaptureRecurrence(freq: "weekly", byDay: ["MO"], count: 5)))
        let sessions = state.events.filter { $0.title == "Standup" }.sorted { $0.start < $1.start }
        XCTAssertEqual(sessions.count, 5)

        // "This event" cancels one occurrence only.
        state.deleteSeries(sessions[0], scope: .thisEvent)
        XCTAssertEqual(state.events.filter { $0.title == "Standup" }.count, 4)

        // "This and following" ends the series from that date on.
        state.deleteSeries(sessions[3], scope: .thisAndFollowing)
        let left = state.events.filter { $0.title == "Standup" }
        XCTAssertEqual(left.count, 2)
        XCTAssertTrue(left.allSatisfy { $0.start < sessions[3].start })

        // "All events" removes what remains.
        state.deleteSeries(left[0], scope: .allEvents)
        XCTAssertTrue(state.events.filter { $0.title == "Standup" }.isEmpty)
    }

    /// Moving a whole series to a new time shifts every session on ITS OWN day — it never
    /// collapses them onto the edited session's date.
    func testUpdateSeriesAllEventsMovesTheTimeNotTheDates() throws {
        let state = AppState()
        state.applyCapture(
            result(kind: "event", title: "Practice", space: "Personal",
                   startISO: "2026-09-07T17:00:00Z", durationMin: 60,
                   recurrence: CaptureRecurrence(freq: "weekly", byDay: ["MO"], count: 4)))
        let sessions = state.events.filter { $0.title == "Practice" }.sorted { $0.start < $1.start }
        let originalDays = sessions.map { Calendar.current.startOfDay(for: $0.start) }

        var edited = sessions[1]
        edited.title = "Practice (moved)"
        edited.start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: edited.start)!
        edited.end = edited.start.addingTimeInterval(90 * 60)
        state.updateSeries(edited, scope: .allEvents)

        let after = state.events.filter { $0.title == "Practice (moved)" }.sorted { $0.start < $1.start }
        XCTAssertEqual(after.count, 4)
        XCTAssertEqual(after.map { Calendar.current.startOfDay(for: $0.start) }, originalDays)
        for session in after {
            XCTAssertEqual(Calendar.current.component(.hour, from: session.start), 14)
            XCTAssertEqual(session.end.timeIntervalSince(session.start), 90 * 60, accuracy: 0.5)
        }
    }

    func testApplyCaptureTaskWithDate() {
        let state = AppState()
        let before = state.tasks.count
        let outcome = state.applyCapture(
            result(kind: "task", title: "Essay", space: "School",
                   dueISO: "2026-07-02T23:59:00Z")).outcome
        XCTAssertEqual(outcome, .task(hasDate: true))
        XCTAssertEqual(state.tasks.count, before + 1)
        XCTAssertNotNil(state.tasks.last?.dueDate)
    }

    func testApplyCaptureTaskWithoutDate() {
        let state = AppState()
        let outcome = state.applyCapture(result(kind: "task", title: "Call dentist")).outcome
        XCTAssertEqual(outcome, .task(hasDate: false))
        XCTAssertNil(state.tasks.last?.dueDate)
    }

    func testApplyCaptureNote() {
        let state = AppState()
        let before = state.notes.count
        let outcome = state.applyCapture(
            result(kind: "note", title: "Idea", notes: "remember this")).outcome
        XCTAssertEqual(outcome, .note)
        XCTAssertEqual(state.notes.count, before + 1)
    }

    func testApplyCaptureEventWithStartAddsEvent() throws {
        let state = AppState()
        let before = state.events.count
        let outcome = state.applyCapture(
            result(kind: "event", title: "Gym", space: "Health",
                   startISO: "2026-06-28T15:00:00Z", durationMin: 45)).outcome
        XCTAssertEqual(outcome, .event)
        XCTAssertEqual(state.events.count, before + 1)
        let added = try XCTUnwrap(state.events.last)
        XCTAssertEqual(added.title, "Gym")
        XCTAssertEqual(added.end.timeIntervalSince(added.start), 45 * 60, accuracy: 0.5)
    }

    func testApplyCaptureEventWithoutStartFallsBackToTask() {
        let state = AppState()
        let eventsBefore = state.events.count
        let tasksBefore = state.tasks.count
        let outcome = state.applyCapture(result(kind: "event", title: "Mystery meeting")).outcome
        XCTAssertEqual(outcome, .task(hasDate: false))
        XCTAssertEqual(state.events.count, eventsBefore)        // no event
        XCTAssertEqual(state.tasks.count, tasksBefore + 1)      // saved as task
    }

    func testApplyCaptureUnknownKindBecomesTask() {
        let state = AppState()
        let outcome = state.applyCapture(result(kind: "wat", title: "Strange")).outcome
        XCTAssertEqual(outcome, .task(hasDate: false))
        XCTAssertEqual(state.tasks.last?.title, "Strange")
    }

    func testMultiItemCaptureConfirmationCount() {
        let state = AppState()
        let results = [
            result(kind: "task", title: "A"),
            result(kind: "note", title: "B"),
            result(kind: "event", title: "C", startISO: "2026-06-28T15:00:00Z"),
        ]
        let outcomes = results.map { state.applyCapture($0).outcome }
        XCTAssertEqual(CaptureOutcome.confirmation(for: outcomes), "✓ Added 3 items")
    }

    func testSingleItemCaptureKeepsPerKindConfirmation() {
        let state = AppState()
        let outcomes = [state.applyCapture(result(kind: "note", title: "Solo")).outcome]
        XCTAssertEqual(CaptureOutcome.confirmation(for: outcomes),
                       CaptureOutcome.note.confirmation)
    }
}
