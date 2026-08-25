import SwiftUI
import AtlasCore

/// The School framework's phone-side behaviour — the iOS twin of the Mac's
/// `AppState+School`: the enable/hide preference, the term lifecycle, class
/// creation/archival, and the Canvas-course catch-up list.
///
/// Deliberately its own file and purely additive to `MobileStore`, so the School
/// wave and the calendar wave never touch the same lines. The pure rules live in
/// `AtlasCore` (`TermSelection`, `SchoolCalendar`); this only wires them to the
/// snapshot and the DB, with the Mac's fire-and-forget persist posture.
@MainActor
extension MobileStore {

    // MARK: - Enable / hide (user_settings.school_enabled)

    /// UserDefaults key mirrored into `user_settings.school_enabled` — the same string
    /// the Mac uses, so the preference is genuinely one setting across devices.
    static let schoolEnabledKey = "school.enabled"

    /// Whether the School tab is shown. Absent ⇒ shown: School hides only when the user
    /// explicitly turned it off, so a student signing in on a new phone keeps it.
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

    var terms: [Term] { snapshot.terms }

    /// The term today falls in (or the nearest sensible one) — see `TermSelection`.
    var activeTerm: Term? { TermSelection.active(in: snapshot.terms) }

    /// Inserts or updates a term locally and persists it. The local array drives the
    /// School list, so it updates even while the write is in flight.
    func saveTerm(_ term: Term) {
        if let i = snapshot.terms.firstIndex(where: { $0.id == term.id }) {
            snapshot.terms[i] = term
        } else {
            snapshot.terms.append(term)
            snapshot.terms.sort { ($0.startsOn ?? .distantPast) < ($1.startsOn ?? .distantPast) }
        }
        Task { try? await self.db.upsertTerm(term) }
    }

    /// Every live class of `term`, the School list's contents.
    func classes(in term: Term) -> [Project] {
        snapshot.projects.filter { $0.isClass && $0.termID == term.id && $0.archivedAt == nil }
    }

    /// Classes that predate the term model — what the one-time "date your term" prompt
    /// adopts into the term it creates.
    var undatedClasses: [Project] {
        snapshot.projects.filter { $0.isClass && $0.termID == nil && $0.archivedAt == nil }
    }

    /// True when there are legacy classes but no term to hang them off yet.
    var unassignedClassesNeedTerm: Bool { snapshot.terms.isEmpty && !undatedClasses.isEmpty }

    /// Files every undated class into `term` — the migration prompt's action.
    func adoptUndatedClasses(into term: Term) {
        for klass in undatedClasses {
            var updated = klass
            updated.termID = term.id
            applyClassEdit(updated)
        }
    }

    // MARK: - Classes

    /// The space classes are created in: an existing "School" space, else the first one.
    /// Never invents a space on the phone — the server seed makes School at sign-up.
    func schoolSpaceName() -> String {
        snapshot.spaces.first { $0.name.caseInsensitiveCompare("School") == .orderedSame }?.name
            ?? snapshot.spaces.first?.name
            ?? "School"
    }

    /// Creates a class in `term`, returning it so the caller can link a Canvas course.
    @discardableResult
    func addClass(name: String, code: String?, termID: UUID?, colorToken: String? = nil) -> Project? {
        let spaceName = schoolSpaceName()
        let space = snapshot.spaces.first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }
        var created = Project(name: name,
                              code: code,
                              isClass: true,
                              spaceName: spaceName,
                              spaceColor: space?.color ?? AtlasTheme.Colors.school)
        created.colorToken = colorToken
        created.spaceID = space?.id
        created.termID = termID
        snapshot.projects.append(created)
        Task { try? await self.db.upsertProject(created) }
        return created
    }

    /// Writes an edited class back into the snapshot and persists it — the single funnel
    /// for every class-shaped edit (term, meeting pattern, instructor, info card).
    func applyClassEdit(_ project: Project) {
        guard let i = snapshot.projects.firstIndex(where: { $0.id == project.id }) else { return }
        snapshot.projects[i] = project
        Task { try? await self.db.upsertProject(project) }
    }

    /// Replaces a class's structured meeting blocks (where every ingestion door lands).
    func setMeetingPattern(projectID: UUID, blocks: [MeetingBlock], meetingInfo: String?) {
        guard var project = snapshot.projects.first(where: { $0.id == projectID }) else { return }
        project.meetingPattern = blocks
        project.meetingInfo = (meetingInfo?.isEmpty ?? true) ? nil : meetingInfo
        applyClassEdit(project)
    }

    func setInstructor(projectID: UUID, instructor: String?) {
        guard var project = snapshot.projects.first(where: { $0.id == projectID }) else { return }
        let trimmed = instructor?.trimmingCharacters(in: .whitespacesAndNewlines)
        project.instructor = (trimmed?.isEmpty ?? true) ? nil : trimmed
        applyClassEdit(project)
    }

    /// Replaces a class's "Class info" card — static syllabus text, never computed.
    func setClassInfo(projectID: UUID, info: ClassInfoCard?) {
        guard var project = snapshot.projects.first(where: { $0.id == projectID }) else { return }
        project.classInfo = info
        applyClassEdit(project)
    }

    /// Soft-archives (or restores) a class. Its tasks and notes stay queryable — a term
    /// ending never wipes coursework.
    func setClassArchived(projectID: UUID, archived: Bool) {
        guard let i = snapshot.projects.firstIndex(where: { $0.id == projectID }) else { return }
        let stamp: Date? = archived ? Date() : nil
        snapshot.projects[i].archivedAt = stamp
        Task { try? await self.db.setProjectArchived(id: projectID, archivedAt: stamp) }
    }

    /// Archives every live class of `term` — the "that semester is over" action.
    func archiveClasses(in term: Term) {
        for klass in classes(in: term) {
            setClassArchived(projectID: klass.id, archived: true)
        }
    }

    // MARK: - Canvas courses without a class

    /// Distinct Canvas course labels present in the synced feed.
    var canvasCoursesInFeed: [String] {
        let labels = snapshot.tasks.compactMap(\.canvasCourse) + snapshot.events.compactMap(\.canvasCourse)
        return Array(Set(labels)).sorted()
    }

    /// Canvas courses no class is linked to yet — the wizard's checklist and the
    /// "N new courses found" prompt read this.
    var unlinkedCanvasCourses: [String] {
        let linked = Set(snapshot.projects.compactMap(\.canvasCourse))
        return canvasCoursesInFeed.filter { !linked.contains($0) }
    }

    /// Creates one class per selected Canvas course under `term`, linking each so that
    /// course's already-imported items file under it (and future ones route there).
    func createClasses(fromCanvasCourses courses: [String], term: Term?) {
        for course in courses {
            guard let created = addClass(name: course, code: nil, termID: term?.id) else { continue }
            linkClassToCanvasCourse(projectID: created.id, course: course)
        }
    }

    /// Links a class to a Canvas course, then re-files that course's already-imported
    /// items under it. Persisting the link routes FUTURE items server-side; the local
    /// arrays plus `remapCanvasCourse` handle the retroactive move — the same split the
    /// Mac uses, so the sync runner's per-tick updates stay user-data-safe.
    func linkClassToCanvasCourse(projectID: UUID, course: String) {
        guard let i = snapshot.projects.firstIndex(where: { $0.id == projectID }) else { return }
        snapshot.projects[i].canvasCourse = course
        let project = snapshot.projects[i]
        Task { try? await self.db.upsertProject(project) }

        let color = project.colorToken.map { ColorToken.color(for: $0) } ?? project.spaceColor
        for j in snapshot.events.indices where snapshot.events[j].canvasCourse == course {
            snapshot.events[j].projectID = project.id
            snapshot.events[j].spaceName = project.spaceName
            snapshot.events[j].spaceID   = project.spaceID
            snapshot.events[j].color     = color
        }
        for j in snapshot.tasks.indices where snapshot.tasks[j].canvasCourse == course {
            snapshot.tasks[j].projectName = project.name
            snapshot.tasks[j].spaceName   = project.spaceName
            snapshot.tasks[j].spaceID     = project.spaceID
            snapshot.tasks[j].spaceColor  = color
        }
        Task { [db] in
            try? await db.remapCanvasCourse(course, toProject: project.id, spaceName: project.spaceName)
        }
    }
}
