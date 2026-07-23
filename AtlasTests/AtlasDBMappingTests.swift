import XCTest
import SwiftUI
@testable import AtlasCore
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

    func testTaskRowDueDateRoundTrip() throws {
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let task = TaskItem(title: "Essay", dueLabel: "", dueDate: due)
        let row = TaskRow(domain: task)
        let decoded = try decoder.decode(TaskRow.self, from: try encoder.encode(row))
        XCTAssertEqual(decoded.dueDate, due, "due_date must survive encode/decode")
        XCTAssertEqual(decoded.toDomain().dueDate, due, "toDomain must restore dueDate")
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

    // MARK: - Canvas source (rule 5) — Task 4

    /// A task carrying a canvas_uid must round-trip the column so a client edit
    /// (complete / schedule) never nulls the Canvas linkage.
    func testTaskRowCanvasUIDRoundTrip() throws {
        var task = TaskItem(title: "Read chapter 4", dueLabel: "Fri", spaceName: "School")
        task.canvasUID = "canvas-assign-4321"
        let row = TaskRow(domain: task)
        XCTAssertEqual(row.canvasUid, "canvas-assign-4321")
        let decoded = try decoder.decode(TaskRow.self, from: try encoder.encode(row))
        XCTAssertEqual(decoded.canvasUid, "canvas-assign-4321", "canvas_uid must survive encode/decode")
        XCTAssertEqual(decoded.toDomain().canvasUID, "canvas-assign-4321", "toDomain must restore canvasUID")
    }

    /// PostgREST returns canvas_uid as a plain string column; decoding must surface it.
    func testTaskRowDecodesCanvasUidFromServerJSON() throws {
        let id = UUID()
        let serverJSON = """
        {"id":"\(id.uuidString)","space_name":"School","title":"Lab 2","status":"open","done":false,"canvas_uid":"c-99"}
        """
        let decoded = try decoder.decode(TaskRow.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(decoded.canvasUid, "c-99")
        XCTAssertEqual(decoded.toDomain().canvasUID, "c-99")
    }

    /// A non-Canvas task has a nil canvasUID (no silent default corruption).
    func testTaskRowNilCanvasUID() throws {
        let task = TaskItem(title: "Personal errand", dueLabel: "")
        let decoded = try decoder.decode(TaskRow.self, from: try encoder.encode(TaskRow(domain: task)))
        XCTAssertNil(decoded.canvasUid)
        XCTAssertNil(decoded.toDomain().canvasUID)
    }

    /// An events row carrying canvas_uid decodes to source .canvas + read-only, and
    /// canvas takes precedence over a google id (canvas-sync stamps both).
    func testEventRowCanvasUidServerJSON() throws {
        let id = UUID()
        let serverJSON = """
        {"id":"\(id.uuidString)","space_name":"School","title":"Midterm","subtitle":"",\
        "start_at":"2026-07-11T17:00:00Z","end_at":"2026-07-11T18:00:00Z","is_all_day":false,\
        "canvas_uid":"c-mid","google_event_id":"g-xyz","google_origin":true}
        """
        let row = try decoder.decode(EventRow.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(row.canvasUid, "c-mid")
        let ev = row.toDomain()
        XCTAssertEqual(ev.source, .canvas, "canvas_uid must win over google_event_id")
        XCTAssertTrue(ev.isReadOnly, "Canvas events are server-owned → read-only")
    }

    // MARK: - Apple event id (Track C mirror) — Task 10 (migration 0026)

    /// An event mirrored to Apple Calendar carries its Apple `eventIdentifier` so a
    /// later edit/delete targets the same EKEvent — the column must round-trip (a
    /// client upsert must never null it), mirroring how google_event_id flows.
    func testEventRowAppleEventIdRoundTrip() throws {
        var event = CalendarEvent(title: "Standup", subtitle: "", start: refDate,
                                  end: refDate.addingTimeInterval(1800),
                                  color: AtlasTheme.Colors.accent, spaceName: "Work")
        event.appleEventId = "apple-evt-ABC-123"
        let row = EventRow(domain: event)
        XCTAssertEqual(row.appleEventId, "apple-evt-ABC-123")
        let decoded = try decoder.decode(EventRow.self, from: try encoder.encode(row))
        XCTAssertEqual(decoded.appleEventId, "apple-evt-ABC-123", "apple_event_id must survive encode/decode")
        XCTAssertEqual(decoded.toDomain().appleEventId, "apple-evt-ABC-123", "toDomain must restore appleEventId")
    }

    /// PostgREST returns apple_event_id as a plain string column; decoding must surface it.
    func testEventRowDecodesAppleEventIdFromServerJSON() throws {
        let id = UUID()
        let serverJSON = """
        {"id":"\(id.uuidString)","space_name":"Work","title":"1:1","subtitle":"",\
        "start_at":"2026-07-11T17:00:00Z","end_at":"2026-07-11T18:00:00Z","is_all_day":false,\
        "apple_event_id":"apple-evt-XYZ-9"}
        """
        let decoded = try decoder.decode(EventRow.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(decoded.appleEventId, "apple-evt-XYZ-9")
        XCTAssertEqual(decoded.toDomain().appleEventId, "apple-evt-XYZ-9")
    }

    /// A task whose scheduled work-block was mirrored to Apple carries the block's
    /// Apple `eventIdentifier`; the column must round-trip so a reschedule patches
    /// the same EKEvent (0005's work_block_google_event_id precedent, for Apple).
    func testTaskRowAppleEventIdRoundTrip() throws {
        var task = TaskItem(title: "Write essay", dueLabel: "Fri", spaceName: "School")
        task.appleEventId = "apple-block-777"
        let row = TaskRow(domain: task)
        XCTAssertEqual(row.appleEventId, "apple-block-777")
        let decoded = try decoder.decode(TaskRow.self, from: try encoder.encode(row))
        XCTAssertEqual(decoded.appleEventId, "apple-block-777", "apple_event_id must survive encode/decode")
        XCTAssertEqual(decoded.toDomain().appleEventId, "apple-block-777", "toDomain must restore appleEventId")
    }

    /// PostgREST returns apple_event_id as a plain string column; decoding must surface it.
    func testTaskRowDecodesAppleEventIdFromServerJSON() throws {
        let id = UUID()
        let serverJSON = """
        {"id":"\(id.uuidString)","space_name":"School","title":"Lab 3","status":"open","done":false,"apple_event_id":"a-42"}
        """
        let decoded = try decoder.decode(TaskRow.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(decoded.appleEventId, "a-42")
        XCTAssertEqual(decoded.toDomain().appleEventId, "a-42")
    }

    /// A task never mirrored to Apple has a nil appleEventId (no silent default corruption).
    func testTaskRowNilAppleEventId() throws {
        let task = TaskItem(title: "Personal errand", dueLabel: "")
        let decoded = try decoder.decode(TaskRow.self, from: try encoder.encode(TaskRow(domain: task)))
        XCTAssertNil(decoded.appleEventId)
        XCTAssertNil(decoded.toDomain().appleEventId)
    }

    // MARK: - NoteRow

    func testNoteRowRoundTrip() throws {
        let note = Note(
            title: "Graph algorithms",
            body: "BFS vs DFS — track visited set.",
            spaceName: "School",
            updatedAt: refDate,
            isExternal: true,
            googleDocId: "doc-abc-123"
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
        XCTAssertEqual(result.googleDocId, "doc-abc-123")
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

    // MARK: - UserSettingsRow (0025)

    func testUserSettingsRowRoundTrip() throws {
        let uid = UUID()
        let row = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "School",
            appleCalendarDefaultSpace: "Personal",
            textScale: 1.25,
            sidebarMode: "hover",
            tasksGrouping: "space",
            perTabDocsSync: false,
            // keys pre-sorted so the compact re-serialization is byte-stable
            notificationPrefsJSON: "{\"morningDigest\":true,\"quietHours\":\"22:00-07:00\"}",
            updatedAt: refDate
        )
        let data = try encoder.encode(row)
        let decoded = try decoder.decode(UserSettingsRow.self, from: data)
        XCTAssertEqual(decoded, row, "every UserSettingsRow field must survive encode/decode")
        XCTAssertEqual(decoded.notificationPrefsJSON,
                       "{\"morningDigest\":true,\"quietHours\":\"22:00-07:00\"}")
    }

    /// The jsonb column must land in the wire body as a RAW JSON object, never a
    /// quoted JSON string — otherwise PostgREST stores `"{...}"` instead of `{...}`.
    func testUserSettingsRowNotificationPrefsEncodesAsRawObject() throws {
        let row = UserSettingsRow(userId: UUID(),
                                  notificationPrefsJSON: "{\"morningDigest\":true}")
        let json = String(data: try encoder.encode(row), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"notification_prefs\":{"),
                      "notification_prefs must serialize as a raw JSON object")
        XCTAssertFalse(json.contains("\"notification_prefs\":\"{"),
                       "notification_prefs must NOT be a quoted JSON string")
    }

    /// PostgREST returns jsonb as a nested JSON object; decoding must collapse it
    /// into the opaque compact string the client carries.
    func testUserSettingsRowDecodesServerJsonbObject() throws {
        let uid = UUID()
        let serverJSON = """
        {"user_id":"\(uid.uuidString)","default_space_name":"School",\
        "notification_prefs":{"morningDigest":true}}
        """
        let decoded = try decoder.decode(UserSettingsRow.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(decoded.userId, uid)
        XCTAssertEqual(decoded.defaultSpaceName, "School")
        XCTAssertEqual(decoded.notificationPrefsJSON, "{\"morningDigest\":true}")
    }

    func testUserSettingsRowNilsDecodeFromMinimalJSON() throws {
        let uid = UUID()
        let minimal = "{\"user_id\":\"\(uid.uuidString)\"}"
        let decoded = try decoder.decode(UserSettingsRow.self, from: Data(minimal.utf8))
        XCTAssertEqual(decoded.userId, uid)
        XCTAssertNil(decoded.defaultSpaceName)
        XCTAssertNil(decoded.appleCalendarDefaultSpace)
        XCTAssertNil(decoded.textScale)
        XCTAssertNil(decoded.sidebarMode)
        XCTAssertNil(decoded.tasksGrouping)
        XCTAssertNil(decoded.perTabDocsSync)
        XCTAssertNil(decoded.notificationPrefsJSON)
        XCTAssertNil(decoded.updatedAt)
    }
}
