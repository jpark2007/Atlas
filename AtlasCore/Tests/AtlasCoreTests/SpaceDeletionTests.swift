import XCTest
@testable import AtlasCore

final class SpaceDeletionTests: XCTestCase {
    private let school = Space(name: "School", color: .blue, projects: [])
    private let personal = Space(name: "Personal", color: .green, projects: [])

    private func verdict(_ space: Space, tasks: [TaskItem] = [], events: [CalendarEvent] = [],
                         notes: [Note] = [], isShared: Bool = false) -> SpaceDeletion.Verdict {
        SpaceDeletion.verdict(for: space, allSpaces: [school, personal], tasks: tasks,
                              events: events, notes: notes, isShared: isShared)
    }

    func testEmptySpaceIsAllowed() {
        XCTAssertEqual(verdict(school), .allowed)
        XCTAssertNil(verdict(school).blockedReason)
    }

    func testLastSpaceIsBlocked() {
        let v = SpaceDeletion.verdict(for: school, allSpaces: [school], tasks: [], events: [],
                                      notes: [], isShared: false)
        XCTAssertEqual(v, .lastSpace)
    }

    func testSharedSpaceIsBlocked() {
        XCTAssertEqual(verdict(school, isShared: true), .shared)
    }

    func testSpaceWithProjectIsBlocked() {
        var s = school
        s.projects = [Project(name: "Bio", isClass: true, spaceName: "School", spaceColor: .blue, spaceID: s.id)]
        XCTAssertEqual(verdict(s), .notEmpty(projects: 1, tasks: 0, events: 0, notes: 0))
    }

    func testItemsMatchByIDOrName() {
        let byID = TaskItem(title: "a", dueLabel: "", spaceName: "Renamed", spaceID: school.id)
        let byName = TaskItem(title: "b", dueLabel: "", spaceName: "School")
        let elsewhere = TaskItem(title: "c", dueLabel: "", spaceName: "Personal", spaceID: personal.id)
        let event = CalendarEvent(title: "e", subtitle: "", start: Date(), end: Date(), color: .blue, spaceName: "School")
        let note = Note(title: "n", body: "", spaceID: school.id)
        let v = verdict(school, tasks: [byID, byName, elsewhere], events: [event], notes: [note])
        XCTAssertEqual(v, .notEmpty(projects: 0, tasks: 2, events: 1, notes: 1))
        XCTAssertEqual(v.blockedReason,
                       "This space still has 2 tasks, 1 event, 1 note. Move or delete them first — only an empty space can be deleted.")
    }

    func testOtherSpacesItemsDoNotBlock() {
        let t = TaskItem(title: "c", dueLabel: "", spaceName: "Personal", spaceID: personal.id)
        XCTAssertEqual(verdict(school, tasks: [t]), .allowed)
    }
}
