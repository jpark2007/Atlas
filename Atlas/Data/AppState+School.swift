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

    /// The term classes get filed under, created silently from today's date if there
    /// isn't one. Semesters are plumbing: the user adds classes, Atlas works out which
    /// semester that is (see `SchoolCalendar.autoTerm`) and never asks. The dates it
    /// picks stay editable from School → Edit term.
    @discardableResult
    func ensureActiveTerm() -> Term {
        if let active = activeTerm { return active }
        let created = SchoolCalendar.autoTerm(on: now)
        saveTerm(created)
        return created
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

    /// Adds imported Key Dates to `term`, skipping ones it already carries. A registrar
    /// file's "Fall Semester Ends" belongs here, on the term, not in the class list.
    func addKeyDates(_ dates: [TermKeyDate], to term: Term) {
        var updated = term
        for date in dates where !updated.keyDates.contains(where: {
            $0.label == date.label && Calendar.current.isDate($0.date, inSameDayAs: date.date)
        }) {
            updated.keyDates.append(date)
        }
        guard updated.keyDates.count != term.keyDates.count else { return }
        updated.keyDates.sort { $0.date < $1.date }
        saveTerm(updated)
    }

    /// Files an imported one-off (an exam, or any other single-occurrence item) as an
    /// EVENT at its time, tied to the class its title named.
    ///
    /// Source attribution, per the house rule: the file was read here, on this machine,
    /// and there is no address to sync back to — so this is an Atlas-native, writable
    /// event, never "read-only from" anywhere. It wears the class's color and carries its
    /// `projectID`; with no class matched it lands unassigned rather than inventing one.
    ///
    /// Idempotent: re-importing the same `.ics` must not mint a second copy of an exam.
    /// A local import carries no UID to key on, so the identity is what the user would
    /// call the same item — same class, same title, same start. Matches the key-date
    /// import's posture above.
    func addImportedEvent(title: String, start: Date, end: Date?, location: String?, classID: UUID?) {
        let klass = classID.flatMap { project($0) }
        let alreadyImported = events.contains {
            $0.projectID == klass?.id
                && $0.title == title
                && $0.start == start
        }
        guard !alreadyImported else { return }
        var event = CalendarEvent(
            title: title,
            subtitle: klass?.name ?? location ?? "",
            start: start,
            end: end ?? start.addingTimeInterval(3600),
            color: klass.map { $0.colorToken.map(ColorToken.color(for:)) ?? $0.spaceColor }
                ?? AtlasTheme.Colors.textSecondary,
            spaceName: klass?.spaceName ?? schoolSpaceNameForDisplay,
            notes: location,
            projectID: klass?.id,
            isReadOnly: false,
            source: .atlas
        )
        event.spaceID = klass?.spaceID
        addEvent(event)
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

    /// Creates a class in `term` — or, with no term named and none active, in the one
    /// Atlas silently creates from today's date. A class never waits on a semester.
    /// Returns the new project so the caller can link it to a Canvas course or navigate.
    @discardableResult
    func addClass(name: String, code: String?, termID: UUID?, colorToken: String? = nil) -> Project? {
        let resolvedTermID = termID ?? ensureActiveTerm().id
        let spaceName = schoolSpaceName()
        guard var created = addProject(toSpaceNamed: spaceName, name: name, code: code, isClass: true) else {
            return nil
        }
        created.termID = resolvedTermID
        created.colorToken = colorToken ?? nextClassColorToken()
        applyClassEdit(created)
        return created
    }

    /// The color the next class gets: the first hue in `classPalette` no live class is
    /// already wearing, else the one used least. Classes are told apart by color all over
    /// the app (sidebar dots, calendar meetings), so "all of them blue" is a bug, not a
    /// default — a class never inherits the space color.
    func nextClassColorToken() -> String {
        var counts: [String: Int] = [:]
        for token in allProjects.filter({ $0.isClass && $0.archivedAt == nil }).compactMap(\.colorToken) {
            counts[token, default: 0] += 1
        }
        // `min(by:)` keeps the first minimal element, so palette order breaks the ties and
        // the first twelve classes of a semester are twelve different hues.
        let palette = AtlasTheme.Colors.classPalette.map { ColorToken.token(for: $0) }
        return palette.min { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? "school"
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

    /// Replaces a class's "Class info" card — the syllabus scan's other product. Static
    /// syllabus text only; nothing here is ever computed or scored.
    func setClassInfo(projectID: UUID, info: ClassInfoCard?) {
        guard var project = project(projectID) else { return }
        project.classInfo = info
        applyClassEdit(project)
    }

    /// Points a class at the syllabus document kept for it in the `syllabi` bucket (0044).
    /// Written only after the upload succeeded — a pointer to nothing is worse than none.
    func setSyllabusPath(projectID: UUID, path: String?) {
        guard var project = project(projectID) else { return }
        project.syllabusPath = path
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

    /// The undo for a bad import: removes every LIVE class of `term`, the meeting blocks
    /// they carried, and that term's Key Dates.
    ///
    /// Classes put away from an earlier semester are soft-archived and are deliberately
    /// left alone — this clears the mess you can see, never the history you filed. Tasks
    /// and events that were tied to a removed class are unfiled, not deleted: a wrong
    /// class list is not a reason to lose work.
    func removeAllClasses(in term: Term?) {
        let doomed = term.map { classes(in: $0) } ?? undatedClasses
        guard !doomed.isEmpty else { return }
        let ids = Set(doomed.map(\.id))

        for si in spaces.indices {
            spaces[si].projects.removeAll { ids.contains($0.id) }
        }
        for id in ids {
            Task { try? await self.db?.deleteProject(id: id) }
        }

        for i in events.indices where events[i].projectID.map(ids.contains) == true {
            events[i].projectID = nil
            let updated = events[i]
            Task { try? await self.db?.upsertEvent(updated) }
        }
        let names = Set(doomed.map(\.name))
        for i in tasks.indices
        where tasks[i].projectID.map(ids.contains) == true || names.contains(tasks[i].projectName) {
            tasks[i].projectName = ""   // the DB's `on delete set null` does the same server-side
            tasks[i].projectID   = nil
        }

        if var term, !term.keyDates.isEmpty {
            term.keyDates = []
            saveTerm(term)
        }
    }

    /// Recreates the shells of `source`'s classes (name / code / color) under `target`.
    /// Deliberately shells only: last semester's assignments are not next semester's.
    func copyClassesForward(from source: Term, to target: Term) {
        for klass in classes(in: source) {
            addClass(name: klass.name, code: klass.code, termID: target.id, colorToken: klass.colorToken)
        }
    }

    // MARK: - The legacy "School" space

    /// The spaces the sidebar lists. With the framework on, class projects belong to the
    /// School section and nowhere else — listing them again under SPACES is the same class
    /// twice. So each space is listed without its live classes, and a space that held
    /// nothing but classes disappears entirely rather than showing an empty School under
    /// a School section.
    ///
    /// Nothing is deleted and nothing is hidden that School doesn't already show: a
    /// non-class project in the School space keeps that space on screen (slimmed to just
    /// that project), and an archived class stays where it always was.
    var visibleSpaces: [Space] {
        guard schoolEnabled else { return spaces }
        return spaces.compactMap { space -> Space? in
            guard space.projects.contains(where: { $0.isClass && $0.archivedAt == nil }) else {
                return isEmptyLegacySchoolSpace(space) ? nil : space
            }
            var slimmed = space
            slimmed.projects = space.projects.filter { !($0.isClass && $0.archivedAt == nil) }
            return slimmed.projects.isEmpty ? nil : slimmed
        }
    }

    private func isEmptyLegacySchoolSpace(_ space: Space) -> Bool {
        guard space.name.caseInsensitiveCompare("School") == .orderedSame,
              space.projects.isEmpty else { return false }
        let holds = { (name: String) in name.caseInsensitiveCompare(space.name) == .orderedSame }
        return !events.contains { holds($0.spaceName) } && !tasks.contains { holds($0.spaceName) }
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
        return SchoolCalendar.meetingEvents(on: day, classes: meetingClasses, term: term)
    }

    /// The active term's Key Dates on `day`, as all-day flags. Deliberately NOT deadline
    /// markers: "Spring break" is not something you owe anybody, so it must not land in
    /// the day's due count.
    func keyDateFlags(on day: Date) -> [CalendarEvent] {
        guard schoolEnabled, let term = activeTerm else { return [] }
        return SchoolCalendar.keyDateFlagEvents(on: day, in: term, spaceName: schoolSpaceNameForDisplay)
    }

    /// The space name Key Date flags wear, so the calendar's space filter treats them like
    /// the rest of School. Read-only lookup — never creates a space.
    var schoolSpaceNameForDisplay: String {
        spaces.first { $0.name.caseInsensitiveCompare("School") == .orderedSame }?.name
            ?? spaces.first?.name
            ?? "School"
    }
}
