import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

/// WS-7 — the pure result-shaping logic behind the ⌘K palette.
/// Shape under test (2026-07-06 redesign): empty query → quick actions only;
/// typed query → fuzzy ranked ACTIVE-only results with Create LAST (alone when
/// nothing matches); `t:`/`e:`/`n:`/`p:` prefixes narrow or browse one type.
final class CommandPaletteTests: XCTestCase {

    // MARK: Fixtures

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func project(_ name: String, code: String? = nil) -> Project {
        Project(name: name, code: code, isClass: false,
                spaceName: "School", spaceColor: .blue)
    }

    private func task(_ title: String, done: Bool = false, due: Date? = nil) -> TaskItem {
        TaskItem(title: title, dueLabel: "", done: done, dueDate: due)
    }

    private func note(_ title: String) -> Note {
        Note(title: title, body: "")
    }

    private func event(_ title: String, end: Date) -> CalendarEvent {
        CalendarEvent(title: title, subtitle: "",
                      start: end.addingTimeInterval(-3600), end: end,
                      color: .blue, spaceName: "School")
    }

    private func action(_ id: String) -> PaletteAction {
        PaletteAction(id: id, title: id, subtitle: "", icon: "circle", run: {})
    }

    private var createTask: PaletteAction {
        PaletteAction(id: CommandPaletteModel.createActionID,
                      title: "Create as task", subtitle: "", icon: "plus.circle.fill", run: {})
    }

    private var createNote: PaletteAction {
        PaletteAction(id: CommandPaletteModel.createNoteActionID,
                      title: "Create note", subtitle: "", icon: "note.text.badge.plus", run: {})
    }

    private var quickActions: [PaletteAction] {
        [action("new-task"), action("completed"), action("new-note"), action("new-event")]
    }

    private func results(_ query: String,
                         projects: [Project] = [],
                         tasks: [TaskItem] = [],
                         notes: [Note] = [],
                         events: [CalendarEvent] = [],
                         scope: PaletteScope = .all) -> [PaletteSection] {
        CommandPaletteModel.results(query: query, projects: projects, tasks: tasks,
                                    notes: notes, events: events, now: now,
                                    quickActions: quickActions,
                                    createTask: createTask, createNote: createNote,
                                    scope: scope)
    }

    // MARK: Empty query → quick actions only

    func testEmptyQueryYieldsQuickActionsOnly() {
        let sections = results("   ",
                               projects: [project("Calculus", code: "MATH 101")],
                               tasks: [task("Essay")],
                               notes: [note("Ideas")])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Quick actions")
        XCTAssertEqual(sections.first?.items.count, quickActions.count)
    }

    // MARK: Create placement

    func testZeroMatchesShowsOnlyCreate() {
        let sections = results("zzz nonexistent", tasks: [task("Essay")])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Create")
        guard case .action(let a)? = sections.first?.items.first else {
            return XCTFail("expected the create action")
        }
        XCTAssertEqual(a.id, CommandPaletteModel.createActionID)
    }

    func testCreateRowIsLastWhenThereAreMatches() {
        let sections = results("essay",
                               projects: [project("Essay Writing")],
                               tasks: [task("Essay draft"), task("Unrelated")],
                               notes: [note("Essay notes")])
        XCTAssertEqual(sections.map(\.title), ["Projects", "Tasks", "Notes", "Create"])
    }

    // MARK: Fuzzy ranking

    func testWordPrefixFuzzyMatch() {
        let projects = [project("Data Structures"), project("World History")]
        let matches = CommandPaletteModel.matchingProjects(query: "dat str", projects: projects)
        XCTAssertEqual(matches.map(\.name), ["Data Structures"])
    }

    func testTitlePrefixOutranksWordPrefix() {
        let tasks = [task("Chess essay"), task("Essay draft")]
        let matches = CommandPaletteModel.matchingTasks(query: "es", tasks: tasks)
        XCTAssertEqual(matches.map(\.title), ["Essay draft", "Chess essay"])
    }

    func testTasksAreSearchableBySubstring() {
        let tasks = [task("Finish the essay"), task("Buy milk"), task("Call mom")]
        let matches = CommandPaletteModel.matchingTasks(query: "essay", tasks: tasks)
        XCTAssertEqual(matches.map(\.title), ["Finish the essay"])
    }

    // MARK: Active-only

    func testDoneTasksAndPastEventsAreExcluded() {
        let sections = results("thing",
                               tasks: [task("thing open"), task("thing done", done: true)],
                               events: [event("thing future", end: now.addingTimeInterval(3600)),
                                        event("thing past", end: now.addingTimeInterval(-3600))])
        let taskTitles = sections.first { $0.title == "Tasks" }?.items.compactMap { item -> String? in
            if case .task(let t) = item { return t.title } else { return nil }
        }
        let eventTitles = sections.first { $0.title == "Events" }?.items.compactMap { item -> String? in
            if case .event(let e) = item { return e.title } else { return nil }
        }
        XCTAssertEqual(taskTitles, ["thing open"])
        XCTAssertEqual(eventTitles, ["thing future"])
    }

    // MARK: Scope prefixes

    func testTaskPrefixNarrowsToTasksPlusCreate() {
        let sections = results("t: essay",
                               projects: [project("Essay Writing")],
                               tasks: [task("Essay draft")],
                               notes: [note("Essay notes")])
        XCTAssertEqual(sections.map(\.title), ["Tasks", "Create"])
    }

    func testBarePrefixBrowsesPendingTasksByDeadline() {
        let sections = results("t:",
                               tasks: [task("Undated"),
                                       task("Done", done: true),
                                       task("Due soon", due: now.addingTimeInterval(3600)),
                                       task("Due later", due: now.addingTimeInterval(7200))])
        XCTAssertEqual(sections.map(\.title), ["Tasks"])   // browse: no Create row
        let titles = sections.first?.items.compactMap { item -> String? in
            if case .task(let t) = item { return t.title } else { return nil }
        }
        XCTAssertEqual(titles, ["Due soon", "Due later", "Undated"])
    }

    func testNotePrefixCreateIsNote() {
        let sections = results("n: fresh idea")
        XCTAssertEqual(sections.map(\.title), ["Create"])
        guard case .action(let a)? = sections.first?.items.first else {
            return XCTFail("expected the create-note action")
        }
        XCTAssertEqual(a.id, CommandPaletteModel.createNoteActionID)
    }

    func testUnknownPrefixIsLiteralText() {
        let sections = results("x: whatever", tasks: [task("x: whatever kept literal")])
        XCTAssertEqual(sections.map(\.title), ["Tasks", "Create"])
    }

    // MARK: Focus notes scope

    func testNotesScopeCreateIsLast() {
        let sections = results("idea", notes: [note("Ideas")], scope: .notes)
        XCTAssertEqual(sections.map(\.title), ["Notes", "Create"])
    }
}
