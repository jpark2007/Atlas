import Foundation
import AtlasCore

/// A titled group of palette results. The view renders these in order; the
/// model (below) decides which appear and how they're ordered. `title` doubles
/// as the SwiftUI identity — section titles are unique within a result set.
struct PaletteSection: Identifiable {
    let title: String
    let items: [CommandResult]
    var id: String { title }
}

/// What the palette searches over. `.notes` is the Focus-mode scope: only notes,
/// and the "Create" row makes a note instead of a task.
enum PaletteScope { case all, notes }

/// A `t:`/`e:`/`n:`/`p:` query prefix narrowing results to one type.
enum PaletteTypeScope { case tasks, events, notes, projects }

/// Pure decision logic for the ⌘K command palette: given a query and the
/// current data, decide which sections to show and in what order. Deliberately
/// free of SwiftUI / `AppState` so it can be unit-tested in isolation.
///
/// Shape (per Drew, 2026-07-06):
///  • Empty query → the quick actions, nothing else.
///  • Typed query → fuzzy word-prefix matching over ACTIVE data only (no done
///    tasks, no past events), ranked best-first so Return opens the top hit.
///  • "Create …" is the LAST section — never a duplicate-typo trap — except
///    that with zero matches it's the only row, so naming something new and
///    hitting Return still creates in one keystroke.
///  • `t:`/`e:`/`n:`/`p:` narrows to one type; the prefix alone browses it.
enum CommandPaletteModel {
    /// Stable id for the persistent "Create …" task row, so the view (and
    /// tests) can find it regardless of the query text it carries.
    static let createActionID = "create-task"

    /// Stable id for the "Create note …" row (Focus scope, or under `n:`).
    static let createNoteActionID = "create-note"

    /// Trimmed + lowercased query; empty when nothing meaningful was typed.
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Scope prefixes

    /// "t: foo" → (.tasks, "foo"). No known prefix → (nil, query). Unknown
    /// letters ("x:") are treated as literal text.
    static func parseScope(_ query: String) -> (type: PaletteTypeScope?, rest: String) {
        let trimmed = query.drop(while: \.isWhitespace)
        let prefixes: [(String, PaletteTypeScope)] = [
            ("t:", .tasks), ("e:", .events), ("n:", .notes), ("p:", .projects)
        ]
        for (prefix, type) in prefixes where trimmed.lowercased().hasPrefix(prefix) {
            return (type, String(trimmed.dropFirst(prefix.count)))
        }
        return (nil, query)
    }

    // MARK: - Fuzzy scoring

    /// Match quality of `query` against `title`, nil when it doesn't match.
    /// Every whitespace-separated query token must land somewhere: as a prefix
    /// of a title word (strong) or a bare substring (weak). A full title-prefix
    /// gets a bonus so "es" ranks "Essay draft" above "Chess essay".
    static func score(query: String, title: String) -> Int? {
        let q = normalized(query)
        guard !q.isEmpty else { return nil }
        let t = title.lowercased()
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        var total = t.hasPrefix(q) ? 3 : 0
        for token in q.split(separator: " ").map(String.init) {
            if words.contains(where: { $0.hasPrefix(token) }) {
                total += 2
            } else if t.contains(token) {
                total += 1
            } else {
                return nil
            }
        }
        return total
    }

    /// Score-then-sort: best match first, `tie` breaking equal scores.
    private static func rank<T>(_ query: String, _ items: [T],
                                title: (T) -> String,
                                tie: (T, T) -> Bool) -> [T] {
        items
            .compactMap { item in score(query: query, title: title(item)).map { (item, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : tie($0.0, $1.0) }
            .map(\.0)
    }

    // MARK: - Per-type matching (ranked) and browse ordering

    static func matchingProjects(query: String, projects: [Project]) -> [Project] {
        rank(query, projects, title: \.name) { $0.name < $1.name }
    }

    static func matchingTasks(query: String, tasks: [TaskItem]) -> [TaskItem] {
        rank(query, tasks, title: \.title, tie: taskOrder)
    }

    /// Notes match on title OR body — a title hit always ranks above a
    /// body-only hit, mirroring `score`'s existing prefix/word bonuses within
    /// each field.
    static func matchingNotes(query: String, notes: [Note]) -> [Note] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        return notes
            .compactMap { note -> (Note, Int)? in
                if let titleScore = score(query: query, title: note.title) {
                    return (note, titleScore + 10)
                }
                if score(query: query, title: note.body) != nil {
                    return (note, 0)
                }
                return nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.updatedAt > $1.0.updatedAt }
            .map(\.0)
    }

    static func matchingEvents(query: String, events: [CalendarEvent]) -> [CalendarEvent] {
        rank(query, events, title: \.title) { $0.start < $1.start }
    }

    /// Deadline order: dated before undated, earliest first, title tiebreak —
    /// same semantics as the dashboard focus list.
    private static func taskOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (da?, db?): return da != db ? da < db : a.title < b.title
        case (_?, nil):      return true
        case (nil, _?):      return false
        case (nil, nil):     return a.title < b.title
        }
    }

    // MARK: - Results

    /// The ordered sections for a query. `now` gates events to upcoming; done
    /// tasks are always excluded (the Completed view owns finished work).
    static func results(query: String,
                        projects: [Project],
                        tasks: [TaskItem],
                        notes: [Note],
                        events: [CalendarEvent] = [],
                        now: Date,
                        quickActions: [PaletteAction],
                        createTask: PaletteAction,
                        createNote: PaletteAction,
                        scope: PaletteScope = .all) -> [PaletteSection] {
        let activeTasks = tasks.filter { !$0.done }
        let upcomingEvents = events.filter { $0.end >= now }

        // Focus-mode notes scope: notes only. Empty query lists recent notes; a
        // typed query ranks matches with the "Create note" row last (it stands
        // alone — and is the instant default — when nothing matches).
        if scope == .notes {
            guard !normalized(query).isEmpty else {
                let recent = notes.sorted { $0.updatedAt > $1.updatedAt }
                return recent.isEmpty ? []
                    : [PaletteSection(title: "Notes", items: recent.map(CommandResult.note))]
            }
            var sections: [PaletteSection] = []
            let n = matchingNotes(query: query, notes: notes)
            if !n.isEmpty {
                sections.append(PaletteSection(title: "Notes", items: n.map(CommandResult.note)))
            }
            sections.append(PaletteSection(title: "Create", items: [.action(createNote)]))
            return sections
        }

        let (typeScope, rest) = parseScope(query)
        let q = normalized(rest)

        // Nothing typed at all → the quick actions, nothing else.
        if q.isEmpty && typeScope == nil {
            return [PaletteSection(title: "Quick actions",
                                   items: quickActions.map(CommandResult.action))]
        }

        var sections: [PaletteSection] = []
        func add(_ title: String, _ items: [CommandResult]) {
            if !items.isEmpty { sections.append(PaletteSection(title: title, items: items)) }
        }
        func wants(_ type: PaletteTypeScope) -> Bool { typeScope == nil || typeScope == type }

        // A bare prefix ("t:") browses the whole type in its natural order.
        if wants(.projects) {
            let p = q.isEmpty ? projects.sorted { $0.name < $1.name }
                              : matchingProjects(query: q, projects: projects)
            add("Projects", p.map(CommandResult.project))
        }
        if wants(.tasks) {
            let t = q.isEmpty ? activeTasks.sorted(by: taskOrder)
                              : matchingTasks(query: q, tasks: activeTasks)
            add("Tasks", t.map(CommandResult.task))
        }
        if wants(.events) {
            let e = q.isEmpty ? upcomingEvents.sorted { $0.start < $1.start }
                              : matchingEvents(query: q, events: upcomingEvents)
            add("Events", e.map(CommandResult.event))
        }
        if wants(.notes) {
            let n = q.isEmpty ? notes.sorted { $0.updatedAt > $1.updatedAt }
                              : matchingNotes(query: q, notes: notes)
            add("Notes", n.map(CommandResult.note))
        }

        // Create comes LAST so Return opens the best match — but only when the
        // typed text could name the new thing, and only for creatable types.
        if !q.isEmpty {
            switch typeScope {
            case nil, .tasks:
                sections.append(PaletteSection(title: "Create", items: [.action(createTask)]))
            case .notes:
                sections.append(PaletteSection(title: "Create", items: [.action(createNote)]))
            case .events, .projects:
                break   // no one-field quick-create for these
            }
        }
        return sections
    }
}
