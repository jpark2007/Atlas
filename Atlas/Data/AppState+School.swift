import SwiftUI
import AtlasCore

/// The School framework's app-side behaviour (phase 1, stage B): the enable/hide
/// preference, term lifecycle, class creation/archival, and the calendar synthesis
/// that turns a term into meetings and Key Date flags.
///
/// The pure rules live in `AtlasCore.SchoolCalendar`; this file only wires them to
/// `AppState`'s collections and the DB.
extension AppState {

    // MARK: - Enable / hide (user_settings.school_enabled)

    /// UserDefaults key mirrored into `user_settings.school_enabled` by
    /// `SettingsSyncService` — see `SettingsSyncService.Key.schoolEnabled`.
    static let schoolEnabledKey = "school.enabled"

    /// Whether the School section is shown. Absent ⇒ shown: School hides only when the
    /// user explicitly turned it off, so a student who signs in on a new device keeps it.
    var schoolEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.schoolEnabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Self.schoolEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.schoolEnabledKey)
            pushSyncedSettings()
            objectWillChange.send()
        }
    }

    // MARK: - Terms

    /// Inserts or updates a term locally and persists it. The local array is the source
    /// of truth for the sidebar, so it is updated even if the write is still in flight.
    func saveTerm(_ term: Term) {
        if let i = terms.firstIndex(where: { $0.id == term.id }) {
            terms[i] = term
        } else {
            terms.append(term)
            terms.sort { ($0.startsOn ?? .distantPast) < ($1.startsOn ?? .distantPast) }
        }
        Task { try? await self.db?.upsertTerm(term) }
    }

    /// Deletes a term. Its classes survive (the FK is `on delete set null`) and resurface
    /// as "needs a term" — deleting a semester must never delete coursework.
    func deleteTerm(_ term: Term) {
        terms.removeAll { $0.id == term.id }
        for si in spaces.indices {
            for pi in spaces[si].projects.indices where spaces[si].projects[pi].termID == term.id {
                spaces[si].projects[pi].termID = nil
            }
        }
        Task { try? await self.db?.deleteTerm(id: term.id) }
    }

    /// The term the School section is showing. `schoolTermOverride` lets the user look at
    /// another term from the header menu without changing what "active" means by date.
    var displayedTerm: Term? {
        if let id = schoolTermOverride, let t = terms.first(where: { $0.id == id }) { return t }
        return activeTerm
    }

    /// Every class in `term`, archived ones included — the archive prompt counts these.
    func allClasses(in term: Term) -> [Project] {
        allProjects.filter { $0.isClass && $0.termID == term.id }
    }

    /// Classes that predate the term model — what the one-time "date your term" prompt
    /// adopts into the term it creates.
    var undatedClasses: [Project] {
        allProjects.filter { $0.isClass && $0.termID == nil && $0.archivedAt == nil }
    }

    /// Files every undated class into `term` — the migration prompt's action.
    func adoptUndatedClasses(into term: Term) {
        for si in spaces.indices {
            for pi in spaces[si].projects.indices
            where spaces[si].projects[pi].isClass
               && spaces[si].projects[pi].termID == nil
               && spaces[si].projects[pi].archivedAt == nil {
                spaces[si].projects[pi].termID = term.id
                let updated = spaces[si].projects[pi]
                Task { try? await self.db?.upsertProject(updated) }
            }
        }
    }

    // MARK: - Classes

    /// The space classes are created in: an existing "School" space, else the first
    /// space, else a School space created on the spot. Never invents a second School.
    func schoolSpaceName() -> String {
        if let school = spaces.first(where: { $0.name.caseInsensitiveCompare("School") == .orderedSame }) {
            return school.name
        }
        if let first = spaces.first { return first.name }
        return addSpace(name: "School", color: AtlasTheme.Colors.school)?.name ?? "School"
    }

    /// Creates a class in `term`. Returns the new project so the caller can link it to a
    /// Canvas course or navigate to it.
    @discardableResult
    func addClass(name: String, code: String?, termID: UUID?, colorToken: String? = nil) -> Project? {
        let spaceName = schoolSpaceName()
        guard var created = addProject(toSpaceNamed: spaceName, name: name, code: code, isClass: true) else {
            return nil
        }
        created.termID = termID
        created.colorToken = colorToken
        applyClassEdit(created)
        return created
    }

    /// Writes an edited class back into `spaces` and persists it — the single funnel for
    /// every class-shaped edit (term, color, meeting pattern, instructor, info card).
    func applyClassEdit(_ project: Project) {
        for si in spaces.indices {
            guard let pi = spaces[si].projects.firstIndex(where: { $0.id == project.id }) else { continue }
            spaces[si].projects[pi] = project
            Task { try? await self.db?.upsertProject(project) }
            return
        }
    }

    /// Replaces a class's structured meeting blocks (the landing place for every
    /// schedule-ingestion door).
    func setMeetingPattern(projectID: UUID, blocks: [MeetingBlock], meetingInfo: String?) {
        guard var project = project(projectID) else { return }
        project.meetingPattern = blocks
        project.meetingInfo = (meetingInfo?.isEmpty ?? true) ? nil : meetingInfo
        applyClassEdit(project)
    }

    func setInstructor(projectID: UUID, instructor: String?) {
        guard var project = project(projectID) else { return }
        let trimmed = instructor?.trimmingCharacters(in: .whitespacesAndNewlines)
        project.instructor = (trimmed?.isEmpty ?? true) ? nil : trimmed
        applyClassEdit(project)
    }

    /// Soft-archives (or restores) a class. Its tasks and notes stay queryable — a term
    /// ending never wipes coursework.
    func setClassArchived(projectID: UUID, archived: Bool) {
        guard var project = project(projectID) else { return }
        let stamp: Date? = archived ? Date() : nil
        project.archivedAt = stamp
        for si in spaces.indices {
            if let pi = spaces[si].projects.firstIndex(where: { $0.id == projectID }) {
                spaces[si].projects[pi].archivedAt = stamp
            }
        }
        Task { try? await self.db?.setProjectArchived(id: projectID, archivedAt: stamp) }
    }

    /// Archives every live class of `term` — the "that semester is over" action.
    func archiveClasses(in term: Term) {
        for klass in classes(in: term) {
            setClassArchived(projectID: klass.id, archived: true)
        }
    }

    /// Recreates the shells of `source`'s classes (name / code / color) under `target`.
    /// Deliberately shells only: last semester's assignments are not next semester's.
    func copyClassesForward(from source: Term, to target: Term) {
        for klass in classes(in: source) {
            addClass(name: klass.name, code: klass.code, termID: target.id, colorToken: klass.colorToken)
        }
    }

    // MARK: - Canvas courses without a class

    /// Canvas course labels present in the feed that no class is linked to yet — the
    /// wizard's checklist and the "N new courses found" prompt read this.
    var unlinkedCanvasCourses: [String] {
        let linked = Set(allProjects.compactMap(\.canvasCourse))
        return canvasCoursesInFeed.filter { !linked.contains($0) }
    }

    /// Creates one class per selected Canvas course under `term` and links each so the
    /// course's already-imported items file under it (and future ones route there).
    func createClasses(fromCanvasCourses courses: [String], term: Term?) {
        for course in courses {
            guard let created = addClass(name: course, code: nil, termID: term?.id) else { continue }
            linkProjectToCanvasCourse(projectID: created.id, course: course)
        }
    }

    // MARK: - Calendar synthesis

    /// The classes whose meetings the calendar should draw: the active term's live ones.
    private var meetingClasses: [Project] {
        guard schoolEnabled, let term = activeTerm else { return [] }
        return classes(in: term)
    }

    /// Class meetings on `day`, as solid class-colored blocks (Phase 2 language: a class
    /// meeting is an EVENT). Synthesized from each class's `meetingPattern`, skipping days
    /// outside the term and days the term marks as a holiday or break.
    ///
    /// These go through cross-calendar dedup like any other event: when the same lecture is
    /// also imported from Google/Apple/school ICS, the titles and times match and the
    /// synthesized Atlas copy wins, carrying the imported copy's source as "also in …".
    /// That is door 2 — attribution, not duplication — with no new matching code.
    func classMeetingEvents(on day: Date) -> [CalendarEvent] {
        guard let term = activeTerm else { return [] }
        let classes = meetingClasses
        guard !classes.isEmpty else { return [] }
        return SchoolCalendar.meetings(on: day, classes: classes, term: term).map { meeting in
            let project = classes.first { $0.id == meeting.classID }
            let color = project?.colorToken.map { ColorToken.color(for: $0) }
                ?? project?.spaceColor
                ?? AtlasTheme.Colors.school
            return CalendarEvent(
                id: GoogleCalendarMapper.stableUUID(
                    from: "class-meeting-\(meeting.classID.uuidString)-\(meeting.start.timeIntervalSince1970)"),
                title: meeting.className,
                subtitle: meeting.location ?? meeting.code ?? "Class",
                start: meeting.start,
                end: meeting.end,
                color: color,
                spaceName: project?.spaceName ?? "School",
                isAllDay: false,
                projectID: meeting.classID,
                // Synthesized from the class's pattern — edited on the class, not the tile.
                isReadOnly: true,
                spaceID: project?.spaceID
            )
        }
    }

    /// The active term's Key Dates on `day`, as all-day flags. Deliberately NOT deadline
    /// markers: "Spring break" is not something you owe anybody, so it must not land in
    /// the day's due count.
    func keyDateFlags(on day: Date) -> [CalendarEvent] {
        guard schoolEnabled, let term = activeTerm else { return [] }
        return SchoolCalendar.keyDates(on: day, in: term).map { keyDate in
            CalendarEvent(
                id: GoogleCalendarMapper.stableUUID(
                    from: "key-date-\(term.id.uuidString)-\(keyDate.label)-\(TermDay.string(from: keyDate.date))"),
                title: keyDate.label,
                subtitle: term.name,
                start: Calendar.current.startOfDay(for: keyDate.date),
                end: Calendar.current.startOfDay(for: keyDate.date),
                color: AtlasTheme.Colors.textSecondary,
                spaceName: schoolSpaceNameForDisplay,
                isAllDay: true,
                isReadOnly: true
            )
        }
    }

    /// The space name Key Date flags wear, so the calendar's space filter treats them like
    /// the rest of School. Read-only lookup — never creates a space.
    private var schoolSpaceNameForDisplay: String {
        spaces.first { $0.name.caseInsensitiveCompare("School") == .orderedSame }?.name
            ?? spaces.first?.name
            ?? "School"
    }
}
