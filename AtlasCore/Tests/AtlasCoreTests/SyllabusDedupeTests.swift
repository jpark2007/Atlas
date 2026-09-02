import XCTest
@testable import AtlasCore

/// Handoff §C4: accepting a scan must never duplicate an existing Canvas task or event.
/// The pairs below are the real ones observed in prod on Drew's Calc I — Canvas names the
/// lecture, the syllabus names the topic, and both land on the same day.
final class SyllabusDedupeTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private func day(_ d: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))!
    }

    private func match(_ draft: String, _ existing: String,
                       draftDay: Int = 9, existingDay: Int = 9) -> Bool {
        SyllabusDedupe.matches(draftTitle: draft, draftDate: day(draftDay),
                               existingTitle: existing, existingDate: day(existingDay),
                               calendar: cal)
    }

    // MARK: - The real duplicate pairs

    func test_prodDuplicatePairs_allMatch() {
        let pairs = [
            ("Rates of change, definition of the derivative", "Lecture 1 Definition of the Derivative"),
            ("Limits of indeterminate form (0/0 only)",       "Lecture 2 Limits of Indeterminate Form"),
            ("The chain rule",                                "Lecture 4 The Chain Rule"),
            ("Continuity",                                    "Lecture 6 Continuity"),
            ("Related rates",                                 "Lecture 13 Related Rates"),
            ("Fundamental theorem of calculus",               "Lecture 19 Fundamental Theorem of Calculus"),
        ]
        for (syllabus, canvas) in pairs {
            XCTAssertTrue(match(syllabus, canvas), "should dedupe: \"\(syllabus)\" vs \"\(canvas)\"")
        }
    }

    // MARK: - Schedule documents (the weekly-module table posted apart from the syllabus)

    /// Rows lifted from "General Psychology — Schedule for Fall 2026": the schedule names
    /// the work one way round, Canvas the other. Importing the schedule must not duplicate
    /// what the Canvas sync already brought in.
    func test_schedulePairs_dedupeAgainstCanvasWording() {
        let pairs = [
            ("DBQ Module 5",            "Module 5 DBQ"),
            ("Module 3 DBQ",            "Module 3 DBQ's Due in Canvas"),
            ("DBQ Module 12",           "Module 12 DBQ"),
            ("PreQuiz Module 1",        "Module 1 PreQuiz"),
            ("Discussion Board Question 7", "Module 7 Discussion Board Question"),
            // Same sitting, two columns of the same row: "Exam 1" / "Midterm 1".
            ("Midterm 1",               "Exam 1"),
            ("Midterm 3",               "Exam 3"),
        ]
        for (schedule, canvas) in pairs {
            XCTAssertTrue(match(schedule, canvas), "should dedupe: \"\(schedule)\" vs \"\(canvas)\"")
        }
    }

    func test_schedulePairs_differentModuleNumbersStayDistinct() {
        // The whole risk of an order-insensitive rule: these share every word but the digit.
        XCTAssertFalse(match("DBQ Module 5", "Module 6 DBQ"))
        XCTAssertFalse(match("PreQuiz Module 1", "Module 2 PreQuiz"))
        XCTAssertFalse(match("Midterm 1", "Midterm 2"))
        XCTAssertFalse(match("Midterm 1", "Final Exam"))
    }

    func test_scheduleTopicRowNeverMatchesWork() {
        XCTAssertFalse(match("Social Psychology", "Module 3 DBQ"))
        XCTAssertFalse(match("Sensation & Perception", "Module 8 DBQ"))
    }

    /// A week-range row commits on the last day of its range; Canvas dates the same work
    /// at 11:59 PM that day. Day granularity is what makes the pair meet.
    func test_weekRangeRowMatchesTheCanvasAssignmentOnTheLastDay() {
        let klass = UUID()
        var canvas = TaskItem(title: "Module 5 DBQ", dueLabel: "",
                              dueDate: cal.date(from: DateComponents(year: 2026, month: 10,
                                                                     day: 2, hour: 23, minute: 59))!)
        canvas.projectID = klass
        let ranged = SyllabusDraftItem(kind: .task, title: "DBQ Module 5",
                                       date: cal.date(from: DateComponents(year: 2026, month: 10,
                                                                           day: 2, hour: 23, minute: 59))!,
                                       notes: "Week 5 · Sept 28-Oct 2",
                                       dateApproximate: true)
        let marked = SyllabusDedupe.markingExisting([SyllabusDraftGroup(items: [ranged],
                                                                       targetClassID: klass)],
                                                    tasks: [canvas], events: [], calendar: cal)
        XCTAssertTrue(marked[0].items[0].alreadyExists)
        XCTAssertFalse(marked[0].items[0].include)
        XCTAssertTrue(marked[0].items[0].dateApproximate, "the flag survives dedupe")
    }

    // MARK: - Controls: different work must still import

    func test_differentTopicSameDay_doesNotMatch() {
        XCTAssertFalse(match("Related rates", "Lecture 6 Continuity"))
    }

    func test_sameLecturePrefixDifferentNumber_doesNotMatch() {
        // "lecture1" is exactly 8 shared characters — the fraction rule is what saves this.
        XCTAssertFalse(match("Lecture 1 Definition of the Derivative",
                             "Lecture 10 Implicit Differentiation"))
    }

    func test_differentClassesOwnExams_areNotComparedAcrossClasses() {
        let calcID = UUID(), chemID = UUID()
        var chemFinal = TaskItem(title: "Final Exam", dueLabel: "", dueDate: day(15))
        chemFinal.projectID = chemID
        let group = SyllabusDraftGroup(items: [SyllabusDraftItem(kind: .task, title: "Final Exam",
                                                                 date: day(15))],
                                       targetClassID: calcID)
        let marked = SyllabusDedupe.markingExisting([group], tasks: [chemFinal], events: [],
                                                    calendar: cal)
        XCTAssertFalse(marked[0].items[0].alreadyExists)
        XCTAssertTrue(marked[0].items[0].include)
    }

    // MARK: - Day granularity

    func test_adjacentDayStillMatches() {
        XCTAssertTrue(match("The chain rule", "Lecture 4 The Chain Rule", draftDay: 10, existingDay: 9))
    }

    func test_threeDaysApartDoesNotMatch() {
        XCTAssertFalse(match("The chain rule", "Lecture 4 The Chain Rule", draftDay: 12, existingDay: 9))
    }

    func test_canvasElevenFiftyNinePMAndSyllabusStatedHour_matchOnTheDay() {
        // The whole point of day granularity: an all-day Canvas due reads as 11:59:59 PM,
        // the syllabus row says 5 PM — never equal to the second, plainly the same work.
        var canvasTask = TaskItem(title: "Lecture 4 The Chain Rule", dueLabel: "",
                                  dueDate: AllDayDate.utc.date(from: DateComponents(year: 2026, month: 9, day: 9))!)
        canvasTask.allDay = true
        let klass = UUID()
        canvasTask.projectID = klass

        let stated = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 17))!
        let group = SyllabusDraftGroup(items: [SyllabusDraftItem(kind: .task, title: "The chain rule",
                                                                 date: stated)],
                                       targetClassID: klass)
        let marked = SyllabusDedupe.markingExisting([group], tasks: [canvasTask], events: [],
                                                    calendar: cal)
        XCTAssertTrue(marked[0].items[0].alreadyExists)
        XCTAssertFalse(marked[0].items[0].include, "a matched row must not commit by default")
        XCTAssertEqual(marked[0].items.count, 1, "a matched row is un-checked, never dropped")
    }

    // MARK: - Events dedupe the same way

    func test_draftEventMatchesExistingEvent() {
        let klass = UUID()
        var existing = CalendarEvent(title: "Calc I Life&Soc Sci Final Exam", subtitle: "",
                                     start: day(15), end: day(15),
                                     color: .clear, spaceName: "School")
        existing.projectID = klass
        let group = SyllabusDraftGroup(items: [SyllabusDraftItem(kind: .event, title: "Final Exam",
                                                                 date: day(15))],
                                       targetClassID: klass)
        let marked = SyllabusDedupe.markingExisting([group], tasks: [], events: [existing],
                                                    calendar: cal)
        XCTAssertTrue(marked[0].items[0].alreadyExists)
    }

    func test_unmatchedRowsStayAccepted() {
        let klass = UUID()
        var canvasTask = TaskItem(title: "Lecture 4 The Chain Rule", dueLabel: "", dueDate: day(9))
        canvasTask.projectID = klass
        let group = SyllabusDraftGroup(items: [SyllabusDraftItem(kind: .task, title: "Read chapter 7",
                                                                 date: day(11))],
                                       targetClassID: klass)
        let marked = SyllabusDedupe.markingExisting([group], tasks: [canvasTask], events: [],
                                                    calendar: cal)
        XCTAssertFalse(marked[0].items[0].alreadyExists)
        XCTAssertTrue(marked[0].items[0].include)
    }
}
