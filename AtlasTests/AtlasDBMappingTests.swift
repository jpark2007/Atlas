import XCTest
import SwiftUI
@testable import Atlas

// MARK: - AtlasDB DTO Mapping Tests (TDD — RED before AtlasDB.swift exists, GREEN after)

final class AtlasDBMappingTests: XCTestCase {

    // Shared iso8601 codec (mirrors AtlasDB's private instances)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Fixed reference date (whole second, no fractional precision issues)
    private let refDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - TaskRow

    func testTaskRowRoundTrip() throws {
        let task = TaskItem(
            title: "Finish DS problem set",
            dueLabel: "Thu",
            status: .dueSoon,
            done: true,
            scheduledAt: refDate,
            spaceName: "School"
        )
        let row = TaskRow(domain: task)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(TaskRow.self, from: data)
        let result = decoded.toDomain()

        XCTAssertEqual(result.id, task.id)
        XCTAssertEqual(result.title, task.title)
        XCTAssertEqual(result.done, task.done)
        XCTAssertEqual(result.status, task.status)
        XCTAssertEqual(result.scheduledAt, task.scheduledAt)
        XCTAssertEqual(result.spaceName, task.spaceName)
    }

    func testTaskStatusDueSoonStringRoundTrip() throws {
        let task = TaskItem(title: "t", dueLabel: "", status: .dueSoon)
        let row = TaskRow(domain: task)

        // .dueSoon must map to "due_soon"
        XCTAssertEqual(row.status, "due_soon")

        let data = try encoder.encode(row)
        let decoded = try decoder.decode(TaskRow.self, from: data)
        XCTAssertEqual(decoded.toDomain().status, .dueSoon)
    }

    func testTaskStatusAllValues() {
        let cases: [(TaskStatus, String)] = [
            (.open, "open"),
            (.dueSoon, "due_soon"),
            (.upcoming, "upcoming"),
            (.submitted, "submitted"),
        ]
        for (status, expected) in cases {
            let task = TaskItem(title: "x", dueLabel: "", status: status)
            let row = TaskRow(domain: task)
            XCTAssertEqual(row.status, expected, "TaskStatus.\(status) should encode to \"\(expected)\"")
            XCTAssertEqual(row.toDomain().status, status, "\"\(expected)\" should decode back to TaskStatus.\(status)")
        }
    }

    // MARK: - EventRow

    func testEventRowRoundTrip() throws {
        let start = refDate
        let end = refDate.addingTimeInterval(3_600)
        let event = CalendarEvent(
            title: "CS 201 Lecture",
            subtitle: "Tech Hall 204",
            start: start,
            end: end,
            color: AtlasTheme.Colors.accent,
            spaceName: "School"
        )
        let row = EventRow(domain: event)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(EventRow.self, from: data)
        let result = decoded.toDomain()

        XCTAssertEqual(result.id, event.id)
        XCTAssertEqual(result.title, event.title)
        XCTAssertEqual(result.subtitle, event.subtitle)
        XCTAssertEqual(result.start, event.start)
        XCTAssertEqual(result.end, event.end)
        XCTAssertEqual(result.spaceName, event.spaceName)
    }

    func testEventRowFutureFieldsDefaultToNilFalse() throws {
        let event = CalendarEvent(
            title: "Gym",
            subtitle: "Rec center",
            start: refDate,
            end: refDate.addingTimeInterval(3600),
            color: AtlasTheme.Colors.accent,
            spaceName: "Personal"
        )
        let row = EventRow(domain: event)
        XCTAssertNil(row.notes)
        XCTAssertFalse(row.isAllDay)
        XCTAssertNil(row.projectId)
    }

    func testEventRowWithNewFieldsRoundTrip() throws {
        let pid = UUID()
        let event = CalendarEvent(title: "T", subtitle: "", start: refDate, end: refDate.addingTimeInterval(3600),
                                  color: AtlasTheme.Colors.accent, spaceName: "School",
                                  notes: "Bring laptop", isAllDay: true, projectID: pid)
        let data = try encoder.encode(EventRow(domain: event))
        let result = try decoder.decode(EventRow.self, from: data).toDomain()
        XCTAssertEqual(result.notes, "Bring laptop")
        XCTAssertTrue(result.isAllDay)
        XCTAssertEqual(result.projectID, pid)
    }

    // MARK: - NoteRow

    func testNoteRowRoundTrip() throws {
        let note = Note(
            title: "Graph algorithms",
            body: "BFS vs DFS — track visited set.",
            spaceName: "School",
            updatedAt: refDate,
            isExternal: true
        )
        let row = NoteRow(domain: note)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(NoteRow.self, from: data)
        let result = decoded.toDomain()

        XCTAssertEqual(result.id, note.id)
        XCTAssertEqual(result.title, note.title)
        XCTAssertEqual(result.body, note.body)
        XCTAssertEqual(result.spaceName, note.spaceName)
        XCTAssertEqual(result.updatedAt, note.updatedAt)
        XCTAssertEqual(result.isExternal, note.isExternal)
    }

    func testNoteRowNilSpaceName() throws {
        let note = Note(title: "Loose note", body: "Some text", spaceName: nil)
        let row = NoteRow(domain: note)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(NoteRow.self, from: data)
        XCTAssertNil(decoded.spaceName)
        XCTAssertNil(decoded.toDomain().spaceName)
    }

    // MARK: - GoalRow

    func testGoalRowRoundTrip() throws {
        let goal = Goal(title: "Ship Trailhead v1", progress: 0.75, label: "3 / 4 milestones")
        let row = GoalRow(domain: goal)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(GoalRow.self, from: data)
        let result = decoded.toDomain()

        XCTAssertEqual(result.id, goal.id)
        XCTAssertEqual(result.title, goal.title)
        XCTAssertEqual(result.progress, goal.progress, accuracy: 0.001)
        XCTAssertEqual(result.label, goal.label)
    }

    // MARK: - SpaceRow

    func testSpaceRowRoundTrip() throws {
        let space = Space(name: "School", color: AtlasTheme.Colors.school, projects: [])
        let row = SpaceRow(domain: space)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(SpaceRow.self, from: data)
        let result = decoded.toDomain()

        XCTAssertEqual(result.id, space.id)
        XCTAssertEqual(result.name, space.name)
        XCTAssertEqual(decoded.colorToken, "school")
        XCTAssertTrue(result.projects.isEmpty,
                      "AtlasSnapshot.spaces return empty projects[] — re-nesting is Task 2")
    }

    func testSpaceRowColorTokens() {
        // Each known space maps to the right token
        let pairs: [(Color, String)] = [
            (AtlasTheme.Colors.school,   "school"),
            (AtlasTheme.Colors.personal, "personal"),
            (AtlasTheme.Colors.side,     "side"),
        ]
        for (color, expected) in pairs {
            let space = Space(name: "Test", color: color, projects: [])
            let row = SpaceRow(domain: space)
            XCTAssertEqual(row.colorToken, expected,
                           "Color should produce token \"\(expected)\"")
        }
    }

    // MARK: - ProjectRow

    func testProjectRowRoundTrip() throws {
        let project = Project(
            name: "Data Structures",
            code: "CS 201",
            isClass: true,
            spaceName: "School",
            spaceColor: AtlasTheme.Colors.school,
            meetingInfo: "MWF · Tech Hall 204",
            instructor: "Prof. Alvarez",
            canvasSynced: true,
            overview: "Core algorithms track class."
        )
        let row = ProjectRow(domain: project)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(ProjectRow.self, from: data)
        let result = decoded.toDomain()

        XCTAssertEqual(result.id, project.id)
        XCTAssertEqual(result.name, project.name)
        XCTAssertEqual(result.code, project.code)
        XCTAssertEqual(result.isClass, project.isClass)
        XCTAssertEqual(result.spaceName, project.spaceName)
        XCTAssertEqual(result.meetingInfo, project.meetingInfo)
        XCTAssertEqual(result.instructor, project.instructor)
        XCTAssertEqual(result.canvasSynced, project.canvasSynced)
        XCTAssertEqual(result.overview, project.overview)

        // Nested display arrays are NOT persisted — toDomain() returns []
        XCTAssertTrue(result.assignments.isEmpty, "assignments not persisted")
        XCTAssertTrue(result.notes.isEmpty,       "notes refs not persisted")
        XCTAssertTrue(result.pinned.isEmpty,      "pinned not persisted")
        XCTAssertTrue(result.backlinks.isEmpty,   "backlinks not persisted")
    }

    func testProjectRowNoCode() throws {
        let project = Project(
            name: "Calculus II",
            code: nil,
            isClass: true,
            spaceName: "School",
            spaceColor: AtlasTheme.Colors.school
        )
        let row = ProjectRow(domain: project)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(ProjectRow.self, from: data)
        XCTAssertNil(decoded.code)
        XCTAssertNil(decoded.toDomain().code)
    }

    // MARK: - DTO id capture (DTO stores domain id; toDomain() produces fresh domain id)

    /// `TaskRow.id` captures the domain TaskItem's UUID — verified here.
    /// NOTE: `toDomain().id` is a FRESH UUID because `TaskItem` uses `let id = UUID()`,
    /// which cannot be set via extension init. Task 2 uses DTO `.id` directly for
    /// DB identity rather than the returned domain object's UUID.
    func testTaskRowCaptutesDomainID() {
        let task = TaskItem(title: "Preserve me", dueLabel: "")
        let row = TaskRow(domain: task)
        XCTAssertEqual(row.id, task.id, "TaskRow must store the domain object's UUID")
    }

    /// CalendarEvent uses `var id: UUID = UUID()` so the memberwise init exposes
    /// `id` as an overridable parameter — the DB UUID IS preserved for events.
    func testEventRowPreservesID() throws {
        let event = CalendarEvent(
            title: "CS Lecture", subtitle: "Hall",
            start: refDate, end: refDate.addingTimeInterval(3600),
            color: AtlasTheme.Colors.accent, spaceName: "School")
        let row = EventRow(domain: event)
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(EventRow.self, from: data)
        XCTAssertEqual(decoded.toDomain().id, event.id,
                       "CalendarEvent UUID must survive the round-trip (var id, not let)")
    }
}
