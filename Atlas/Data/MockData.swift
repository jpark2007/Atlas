import SwiftUI

/// Sample data mirroring the approved prototype. Swap for Supabase later.
enum MockData {
    /// Build a `Date` at a given hour/minute on today's date.
    static func todayAt(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static let events: [CalendarEvent] = [
        .init(title: "CS 201 Lecture",   subtitle: "Tech Hall 204",     start: todayAt(9),        end: todayAt(10, 15), color: AtlasTheme.Colors.school,   spaceName: "School"),
        .init(title: "Calculus II",      subtitle: "Recitation",        start: todayAt(11),       end: todayAt(12),     color: AtlasTheme.Colors.school,   spaceName: "School"),
        .init(title: "Lunch w/ Dev team", subtitle: "Trailhead standup", start: todayAt(13),       end: todayAt(14),     color: AtlasTheme.Colors.side,     spaceName: "Side Project"),
        .init(title: "Gym — push day",   subtitle: "Recreation center", start: todayAt(16),       end: todayAt(17),     color: AtlasTheme.Colors.personal, spaceName: "Personal"),
        .init(title: "Dinner with mom",  subtitle: "Personal",          start: todayAt(18, 30),   end: todayAt(20),     color: AtlasTheme.Colors.personal, spaceName: "Personal"),
    ]

    static let tasks: [TaskItem] = [
        .init(title: "Finish DS problem set",     dueLabel: "Thu", spaceColor: AtlasTheme.Colors.school,   spaceName: "School"),
        .init(title: "Calc practice problems",    dueLabel: "Wed", spaceColor: AtlasTheme.Colors.school,   spaceName: "School"),
        .init(title: "Read History ch. 7",        dueLabel: "Fri", spaceColor: AtlasTheme.Colors.school,   spaceName: "School"),
        .init(title: "Design onboarding screens", dueLabel: "",    spaceColor: AtlasTheme.Colors.side,     spaceName: "Side Project"),
        .init(title: "Grocery run",               dueLabel: "",    spaceColor: AtlasTheme.Colors.personal, spaceName: "Personal"),
    ]

    static let notes: [Note] = [
        .init(title: "Midterm study plan", body: "Cover trees, heaps, and graph traversal. Re-derive Dijkstra from scratch. Pair complexity analysis with [[Calculus II]] limit review before the midterm.", spaceName: "School"),
        .init(title: "Graph algorithms", body: "Graph traversal — BFS vs DFS. Remember to track visited set. Priority-queue impl reused from [[Trailhead App]].", spaceName: "School"),
        .init(title: "Trailhead launch checklist", body: "Onboarding screens, app icon, TestFlight build, landing page copy.", spaceName: "Side Project"),
    ]

    static let goals: [Goal] = [
        .init(title: "Get fit",          progress: 0.66, label: "2 / 3 this week"),
        .init(title: "Learn Spanish",    progress: 0.33, label: "1 / 3 blocks"),
        .init(title: "Ship Trailhead v1", progress: 0.60, label: "60%"),
    ]

    static let spaces: [Space] = {
        let blue = AtlasTheme.Colors.school
        let green = AtlasTheme.Colors.personal
        let purple = AtlasTheme.Colors.side

        let dataStructures = Project(
            name: "Data Structures",
            code: "CS 201",
            isClass: true,
            spaceName: "School",
            spaceColor: blue,
            meetingInfo: "MWF · Tech Hall 204",
            instructor: "Prof. Alvarez",
            canvasSynced: true,
            overview: "Core class for the algorithms track. The complexity-analysis unit pairs tightly with Calculus II — review limits before the midterm. Keep every worked problem in the Finish DS problem set task. The priority-queue reference implementation lives in the Trailhead App repo so we reuse it there.",
            assignments: [
                .init(title: "Problem Set 4 — Graphs",  dueLabel: "Thu, Jun 26", status: .dueSoon),
                .init(title: "Reading: Ch. 7 Traversal", dueLabel: "Mon, Jun 30", status: .upcoming),
                .init(title: "Project: Hash-map impl",   dueLabel: "Jul 10",      status: .upcoming),
                .init(title: "Problem Set 3 — Heaps",    dueLabel: "Jun 19",      status: .submitted, done: true),
            ],
            notes: [
                .init(title: "Midterm study plan",   subtitle: "Cover trees, heaps, and graph traversal. Re-derive Dijkstra…"),
                .init(title: "Lecture notes (shared)", subtitle: "Google Doc · linked", isExternal: true),
            ],
            pinned: [
                .init(title: "cs201-psets",        source: "github.com/jordan", systemImage: "chevron.left.forwardslash.chevron.right"),
                .init(title: "Lecture 12 — Dijkstra", source: "youtube.com",     systemImage: "play.rectangle.fill"),
                .init(title: "Deep Focus",         source: "Spotify playlist",  systemImage: "music.note"),
            ],
            backlinks: [
                .init(title: "Finish DS problem set", meta: "Task · School · due Thu",        color: blue),
                .init(title: "CS 201 Lecture",        meta: "Event · Today 9:00 AM",          color: AtlasTheme.Colors.accent),
                .init(title: "Midterm study plan",    meta: "Note · references this class",   color: AtlasTheme.Colors.textSecondary),
                .init(title: "Calculus II",           meta: "Class · shared complexity notes", color: blue),
            ]
        )

        return [
            Space(name: "School", color: blue, projects: [
                dataStructures,
                Project(name: "Calculus II",   code: nil, isClass: true, spaceName: "School", spaceColor: blue),
                Project(name: "World History", code: nil, isClass: true, spaceName: "School", spaceColor: blue),
            ]),
            Space(name: "Personal", color: green, projects: [
                Project(name: "Fitness", code: nil, isClass: false, spaceName: "Personal", spaceColor: green),
                Project(name: "Errands", code: nil, isClass: false, spaceName: "Personal", spaceColor: green),
            ]),
            Space(name: "Side Project", color: purple, projects: [
                Project(name: "Trailhead App", code: nil, isClass: false, spaceName: "Side Project", spaceColor: purple),
            ]),
        ]
    }()
}
