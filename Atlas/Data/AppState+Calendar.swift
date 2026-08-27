import SwiftUI
import AtlasCore

/// Calendar-feature helpers on the shared store. METHODS ONLY (no stored
/// properties) so this stays additive and merge-safe. The event/task source of
/// truth lives on `AppState` itself (`events`, `events(on:)`, `unscheduledTasks`,
/// `schedule(taskId:at:)`); these are just lookups the Calendar UI needs.
extension AppState {

    /// Brand color for a space name, falling back to the accent.
    func calendarSpaceColor(named name: String) -> Color {
        spaces.first { $0.name == name }?.color ?? AtlasTheme.Colors.accent
    }

    // MARK: - Per-project day-grid colors (Option B)

    /// The color a DAY/WEEK-GRID tile should wear: the tile's project color when
    /// that project set its own `colorToken`, else the space color already on the
    /// event. Applied ONLY to grid tiles — month dots, chips, sidebar and routing
    /// keep the space color untouched.
    ///
    /// Association: work-blocks (id == task.id) resolve through the backing task's
    /// project (name + space); other events resolve through `projectID`. An event
    /// with no project link, or whose project has no custom token, is returned
    /// unchanged (space color) — today's exact behavior.
    func gridColored(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.map { ev in
            guard let token = projectColorToken(for: ev) else { return ev }
            var e = ev
            e.color = ColorToken.color(for: token)
            return e
        }
    }

    /// The custom color token of the project a grid tile belongs to, or `nil` when
    /// the tile has no project link / the project inherits the space color.
    private func projectColorToken(for event: CalendarEvent) -> String? {
        if event.isWorkBlock, let task = tasks.first(where: { $0.id == event.id }) {
            return projectColorToken(spaceName: task.spaceName, projectName: task.projectName)
        }
        if let pid = event.projectID,
           let project = spaces.flatMap(\.projects).first(where: { $0.id == pid }) {
            return project.colorToken
        }
        return nil
    }

    /// The custom color token of the project matching `projectName` inside `spaceName`
    /// (empty name ⇒ no project). `nil` when nothing matches or the project inherits.
    private func projectColorToken(spaceName: String, projectName: String) -> String? {
        project(spaceName: spaceName, projectName: projectName)?.colorToken
    }

    /// THE resolver: the project (a class, when `isClass`) a task belongs to. `projectID`
    /// is authoritative — it is what persists — and the name pair is the fallback for
    /// tasks written before the id round-tripped (and for MockData). Every surface that
    /// wants a task's class goes through here, so none of them can drift apart.
    /// `nil` when the task carries no project link or nothing matches.
    func project(for task: TaskItem) -> Project? {
        if let pid = task.projectID,
           let byID = spaces.flatMap(\.projects).first(where: { $0.id == pid }) {
            return byID
        }
        return project(spaceName: task.spaceName, projectName: task.projectName)
    }

    func project(spaceName: String, projectName: String) -> Project? {
        guard !projectName.isEmpty else { return nil }
        return spaces.flatMap(\.projects)
            .first { $0.name == projectName && $0.spaceName == spaceName }
    }

    /// The color a TASK should wear on the unscheduled rail: its project's own
    /// `colorToken` when that project set one (so a class task reads in the class's
    /// color), else the space color already on the task — which itself falls back to
    /// the neutral accent. Same resolution `gridColored` uses for day-grid tiles, so
    /// the rail and the grid can never disagree about a class's color.
    func taskAccentColor(for task: TaskItem) -> Color {
        guard let token = project(for: task)?.colorToken else {
            return task.spaceColor
        }
        return ColorToken.color(for: token)
    }

    /// The chip a TASK row should wear as its PRIMARY identity: its class/project,
    /// preferring the short course code ("CS 201") over the full name, so a row reads
    /// as the class it belongs to rather than the space it sits in. `nil` when the task
    /// has no project — those rows keep the space tag.
    func taskClassChipText(for task: TaskItem) -> String? {
        guard let project = project(for: task) else { return nil }
        let code = (project.code ?? "").trimmingCharacters(in: .whitespaces)
        return code.isEmpty ? project.name : code
    }

    // MARK: - The one display pool

    /// EVERYTHING a calendar surface should draw for `day` — the single pool the
    /// Calendar tab, the dashboard mini-month and the menu-bar agenda all read, so the
    /// three can never disagree about what is on a day.
    ///
    /// Store events (Atlas/Google/Canvas) + scheduled work-blocks + task deadline
    /// markers + synthesized class meetings + read-only Apple externals + term Key Date
    /// flags, collapsed so the same real block arriving from several calendars shows once.
    ///
    /// Key Date flags now go THROUGH dedup rather than around it: a registrar holiday and
    /// the Google/Apple copy of the same holiday are one day-label, not two. That is safe
    /// because a match needs both a normalized-title match AND — for all-day items — the
    /// same UTC calendar date, so a pure label like "Add/drop ends" can never absorb a
    /// timed block. The flag is the Atlas-native copy, so dedup keeps it as the winner.
    ///
    /// Each event keeps its own source and read-only attribution — merging never
    /// relabels where something came from.
    func displayEvents(on day: Date) -> [CalendarEvent] {
        let pool = events(on: day)
            + scheduledWorkBlocks(on: day)
            + deadlineEvents(on: day)
            + classMeetingEvents(on: day)
            + externalEvents(on: day)
            + keyDateFlags(on: day)
        return CalendarSync.collapsingDuplicates(pool, workSessionPrefix: workSessionTitlePrefix)
    }

    /// Deadline markers for `day`: one per open task whose `dueDate` falls there, plus a
    /// faded HISTORY marker at the original due date of anything rescheduled off the Late
    /// bar (so a missed date never silently vanishes).
    ///
    /// Deadlines are never blocks — the grid draws them as hairlines. Colour is the task's
    /// own space/class colour (colour = whose, never what); the ONE state override is red
    /// for "due today and no work time planned", the single place red is earned. Overdue
    /// stays in its own colour here and is surfaced in amber by the Late bar instead.
    /// Deadlines stay in Atlas — they are never pushed to Google.
    func deadlineEvents(on day: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        var markers: [CalendarEvent] = []
        for task in tasks {
            guard !task.done else { continue }
            if let due = task.dueDate, cal.isDate(due, inSameDayAs: day) {
                let red = TimeModel.isDueTodayUnplanned(task, now: now)
                markers.append(CalendarEvent(
                    id: GoogleCalendarMapper.stableUUID(from: "deadline-" + task.id.uuidString),
                    title: task.title,
                    subtitle: "Due",
                    start: due,
                    end: due,
                    color: red ? AtlasTheme.Colors.danger : task.spaceColor,
                    spaceName: task.spaceName,
                    // Never packed as a time block either way — drawn as a rule on the grid.
                    // A due date carrying a real clock time is NOT all-day, so it draws only
                    // as its rule; a date-only due stays all-day and rides the pinned strip.
                    isAllDay: !hasClockTime(due),
                    isDeadline: true,
                    deadlineTaskID: task.id
                ))
            }
            // The original date keeps a faded marker in the past after a late-reschedule.
            if let original = task.originalDueDate, original != task.dueDate,
               cal.isDate(original, inSameDayAs: day) {
                markers.append(CalendarEvent(
                    id: GoogleCalendarMapper.stableUUID(from: "was-due-" + task.id.uuidString),
                    title: "Was due · " + task.title,
                    subtitle: "Originally due",
                    start: original,
                    end: original,
                    color: AtlasTheme.Colors.textMuted,
                    spaceName: task.spaceName,
                    isAllDay: !hasClockTime(original),
                    isDeadline: true,
                    isHistory: true
                ))
            }
        }
        return markers
    }

    /// Whether a due date carries a real clock time (not bare-date midnight). Mirrors
    /// `CalendarEvent.hasSpecificTime`, but has to be answered before the event is built.
    private func hasClockTime(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.hour, from: date) != 0 || cal.component(.minute, from: date) != 0
    }

    // MARK: - External (Apple) events — the one fetch path

    /// Fetch read-only Apple Calendar events for `start..<end` and publish them to
    /// `externalEvents`. The ONLY place EventKit is read for display, so every surface
    /// that needs externals for its own range (the Calendar tab's mode range, the
    /// mini-month's visible grid) goes through here instead of showing a stale pool.
    ///
    /// Google is NOT read here: server-owned cloud sync owns Google↔DB, so Google events
    /// arrive as `events` rows via `loadAll()`. A Mac-local Google pull would double-show
    /// them on top of the synced rows.
    ///
    /// The per-calendar hide list from Settings is applied HERE, not at the call site, so
    /// every surface that refreshes (Calendar tab, dashboard mini-month) respects the
    /// unchecked calendars — otherwise a hidden calendar leaks back in via whichever
    /// surface fetched last.
    func refreshExternalEvents(start: Date, end: Date) async {
        let enabled = UserDefaults.standard.bool(forKey: "calendar.apple.enabled")
        guard enabled, eventKit.authorizationStatus() == .fullAccess else {
            if !externalEvents.isEmpty { externalEvents = [] }
            return
        }
        let stored = UserDefaults.standard.string(forKey: "calendar.apple.defaultSpace") ?? ""
        let defaultSpace = stored.isEmpty ? (spaces.first?.name ?? "") : stored
        let hidden = AppleCalendarSelection.decode(
            UserDefaults.standard.string(forKey: AppleCalendarSelection.hiddenKey) ?? "")

        let combined = await eventKit.fetchEvents(
            start: start, end: end, defaultSpaceName: defaultSpace,
            hiddenCalendarIds: hidden)

        // Drop any Apple event that is actually one of our own events we already mirrored
        // via the Atlas→Apple toggle (EventKit re-reads it next tick). Otherwise it shows
        // twice: once native, once as its read-only Apple copy. Work sessions mirror to
        // Apple too, and their handle lives on the TASK — so their ids must join the
        // drop-set or every mirrored session double-displays as its own "Work: …" copy.
        let ownAppleIDs = Set(events.compactMap(\.appleEventId))
            .union(tasks.compactMap(\.appleEventId))
        externalEvents = CalendarSync.excludingOwnMirrors(
            external: combined, ownGoogleIDs: [], ownAppleIDs: ownAppleIDs)
    }

    /// Resolve a space name to its id for dual-writing `spaceID` alongside
    /// `spaceName` (collab phase 1). Nil when no space matches — the row then
    /// relies on the name fallback exactly as before.
    func spaceID(named name: String) -> UUID? {
        spaces.first { $0.name == name }?.id
    }

    // MARK: - Auto-find-a-slot

    /// Busy `[start, end)` intervals on `day`: the day's timed events plus any
    /// tasks already scheduled there (`scheduledAt` + `durationMin`, default 60).
    /// All-day events are ignored — they don't block a time slot. `excludingTask`
    /// drops one task's own block so a re-suggest doesn't collide with itself.
    func busyIntervals(on day: Date, excludingTask excluded: UUID? = nil) -> [DateInterval] {
        let cal = Calendar.current
        var intervals: [DateInterval] = []

        for ev in events(on: day) where !ev.isAllDay && ev.end > ev.start {
            intervals.append(DateInterval(start: ev.start, end: ev.end))
        }
        for task in tasks {
            guard task.id != excluded,
                  let at = task.scheduledAt,
                  cal.isDate(at, inSameDayAs: day) else { continue }
            let end = at.addingTimeInterval(TimeInterval((task.durationMin ?? 60) * 60))
            intervals.append(DateInterval(start: at, end: end))
        }
        return intervals
    }

    /// Suggests the first free slot on `day` that fits `task` (default 60 min),
    /// within the visible hours, snapped to 15 min, never in the past. nil if the
    /// day is full. The tray's "Suggest time" action feeds this into `schedule`.
    func suggestSlot(for task: TaskItem, on day: Date, now: Date = Date()) -> Date? {
        SlotFinder.firstFreeSlot(
            durationMin: task.durationMin ?? 60,
            on: day,
            busy: busyIntervals(on: day, excludingTask: task.id),
            now: now
        )
    }
}
