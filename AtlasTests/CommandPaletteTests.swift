import XCTest
import SwiftUI
@testable import Atlas

/// WS-7 — the pure result-shaping logic behind the ⌘K palette.
final class CommandPaletteTests: XCTestCase {

    // MARK: Fixtures

    private func project(_ name: String, code: String? = nil) -> Project {
        Project(name: name, code: code, isClass: false,
                spaceName: "School", spaceColor: .blue)
    }

    private func task(_ title: String) -> TaskItem {
        TaskItem(title: title, dueLabel: "")
    }

    private func note(_ title: String) -> Note {
        Note(title: title, body: "")
    }

    private func action(_ id: String) -> PaletteAction {
        PaletteAction(id: id, title: id, subtitle: "", icon: "circle", run: {})
    }

    private func createAction(_ query: String) -> PaletteAction {
        PaletteAction(id: CommandPaletteModel.createActionID,
                      title: "Create \(query) as task",
                      subtitle: "", icon: "plus.circle.fill", run: {})
    }

    private var quickActions: [PaletteAction] {
        [action("metrics"), action("new-task"), action("new-note")]
    }

    /// Pull the leading result's PaletteAction, if any.
    private func leadingAction(_ sections: [PaletteSection]) -> PaletteAction? {
        guard case .action(let a)? = sections.first?.items.first else { return nil }
        return a
    }

    // MARK: Empty query → quick actions only

    func testEmptyQueryYieldsQuickActionsOnly() {
        let sections = CommandPaletteModel.results(
            query: "   ",
            projects: [project("Calculus", code: "MATH 101")],
            tasks: [task("Essay")],
            notes: [note("Ideas")],
            quickActions: quickActions,
            createAction: createAction(""))

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Quick actions")
        XCTAssertEqual(sections.first?.items.count, quickActions.count)
        // No Create row when the query is empty.
        XCTAssertNotEqual(leadingAction(sections)?.id, CommandPaletteModel.createActionID)
    }

    // MARK: Non-empty query → leading Create action

    func testNonEmptyQueryWithNoMatchesLeadsWithCreate() {
        let sections = CommandPaletteModel.results(
            query: "zzz nonexistent",
            projects: [project("Calculus")],
            tasks: [task("Essay")],
            notes: [note("Ideas")],
            quickActions: quickActions,
            createAction: createAction("zzz nonexistent"))

        XCTAssertEqual(sections.first?.title, "Create")
        XCTAssertEqual(leadingAction(sections)?.id, CommandPaletteModel.createActionID)
        // Nothing matched, so Create is the only section.
        XCTAssertEqual(sections.count, 1)
    }

    func testCreateRowLeadsEvenWhenThereAreMatches() {
        let sections = CommandPaletteModel.results(
            query: "essay",
            projects: [project("Essay Writing")],
            tasks: [task("Essay draft"), task("Unrelated")],
            notes: [note("Essay notes")],
            quickActions: quickActions,
            createAction: createAction("essay"))

        // Create is still first…
        XCTAssertEqual(sections.first?.title, "Create")
        XCTAssertEqual(leadingAction(sections)?.id, CommandPaletteModel.createActionID)
        // …followed by the matching sections.
        let titles = sections.map(\.title)
        XCTAssertEqual(titles, ["Create", "Projects", "Tasks", "Notes"])
    }

    // MARK: Tasks are searchable

    func testTasksAreSearchableByTitleSubstring() {
        let tasks = [task("Finish the essay"), task("Buy milk"), task("Call mom")]
        let matches = CommandPaletteModel.matchingTasks(query: "essay", tasks: tasks)
        XCTAssertEqual(matches.map(\.title), ["Finish the essay"])
    }

    func testTaskMatchesAppearInResultsSection() {
        let sections = CommandPaletteModel.results(
            query: "milk",
            projects: [],
            tasks: [task("Buy milk")],
            notes: [],
            quickActions: quickActions,
            createAction: createAction("milk"))

        let taskSection = sections.first { $0.title == "Tasks" }
        XCTAssertNotNil(taskSection)
        XCTAssertEqual(taskSection?.items.count, 1)
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertTrue(CommandPaletteModel.matchingTasks(query: "  ", tasks: [task("X")]).isEmpty)
        XCTAssertTrue(CommandPaletteModel.matchingProjects(query: "", projects: [project("X")]).isEmpty)
        XCTAssertTrue(CommandPaletteModel.matchingNotes(query: "", notes: [note("X")]).isEmpty)
    }
}
