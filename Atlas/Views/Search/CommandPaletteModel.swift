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

/// Pure decision logic for the ⌘K command palette: given a query and the
/// current data, decide which sections to show and in what order. Deliberately
/// free of SwiftUI / `AppState` so it can be unit-tested in isolation.
enum CommandPaletteModel {
    /// Stable id for the persistent "Create …" row, so the view (and tests) can
    /// find it regardless of the query text it carries.
    static let createActionID = "create-task"

    /// Trimmed + lowercased query; empty when nothing meaningful was typed.
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func matchingProjects(query: String, projects: [Project]) -> [Project] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        return projects.filter {
            $0.name.lowercased().contains(q) || ($0.code?.lowercased().contains(q) ?? false)
        }
    }

    static func matchingTasks(query: String, tasks: [TaskItem]) -> [TaskItem] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        return tasks.filter { $0.title.lowercased().contains(q) }
    }

    static func matchingNotes(query: String, notes: [Note]) -> [Note] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        return notes.filter { $0.title.lowercased().contains(q) }
    }

    static func matchingEvents(query: String, events: [CalendarEvent]) -> [CalendarEvent] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        return events.filter { $0.title.lowercased().contains(q) }
    }

    /// The ordered sections for a query.
    ///
    /// - Empty query → a single "Quick actions" section (no Create row).
    /// - Non-empty query → a leading "Create" section carrying `createAction`
    ///   (always first, even when there ARE matches — and especially when there
    ///   are none), followed by any non-empty Projects / Tasks / Notes sections.
    static func results(query: String,
                        projects: [Project],
                        tasks: [TaskItem],
                        notes: [Note],
                        events: [CalendarEvent] = [],
                        quickActions: [PaletteAction],
                        createAction: PaletteAction) -> [PaletteSection] {
        guard !normalized(query).isEmpty else {
            return [PaletteSection(title: "Quick actions",
                                   items: quickActions.map(CommandResult.action))]
        }

        var sections: [PaletteSection] = [
            PaletteSection(title: "Create", items: [.action(createAction)])
        ]

        let p = matchingProjects(query: query, projects: projects)
        if !p.isEmpty {
            sections.append(PaletteSection(title: "Projects",
                                           items: p.map(CommandResult.project)))
        }
        let t = matchingTasks(query: query, tasks: tasks)
        if !t.isEmpty {
            sections.append(PaletteSection(title: "Tasks",
                                           items: t.map(CommandResult.task)))
        }
        let n = matchingNotes(query: query, notes: notes)
        if !n.isEmpty {
            sections.append(PaletteSection(title: "Notes",
                                           items: n.map(CommandResult.note)))
        }
        let e = matchingEvents(query: query, events: events)
        if !e.isEmpty {
            sections.append(PaletteSection(title: "Events",
                                           items: e.map(CommandResult.event)))
        }
        return sections
    }
}
