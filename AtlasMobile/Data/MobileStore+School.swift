import SwiftUI
import AtlasCore

/// The School framework's phone-side behaviour — the iOS twin of the Mac's
/// `AppState+School`: the enable/hide preference, the term lifecycle, class
/// creation/archival.
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

    // MARK: - Scan provenance (0046)

    /// Records one commit of the syllabus-scan sheet and returns the receipt, so the
    /// caller can stamp `scanID` on everything that commit creates. Local first (the
    /// source line reads without a reload). The DB insert is AWAITED — `tasks.scan_id`/
    /// `events.scan_id` are FK-constrained to this row (0046), so the caller must let
    /// this finish before writing anything that points at `scan.id`, or the item write
    /// can reach Supabase first and fail its FK check (23503), silently swallowed by
    /// `try?` and lost on the next reload. Mirrors `AppState.recordScan`.
    @discardableResult
    func recordScan(fileName: String, kind: String, projectID: UUID?) async -> ScanRecord {
        let scan = ScanRecord(projectID: projectID, fileName: fileName, kind: kind)
        snapshot.scans.insert(scan, at: 0)
        try? await self.db.insertScan(scan)
        return scan
    }

    /// The scan receipt an imported item points at, or nil when it has none (hand-made)
    /// or the receipt hasn't loaded. Never guesses a source (CLAUDE.md rule 5).
    func scan(_ id: UUID?) -> ScanRecord? {
        guard let id else { return nil }
        return snapshot.scans.first { $0.id == id }
    }

    // MARK: - Classes

    /// The space classes are created in: an existing "School" space, else the first one.
    /// Never invents a space on the phone — the server seed makes School at sign-up.
    func schoolSpaceName() -> String {
        snapshot.spaces.first { $0.name.caseInsensitiveCompare("School") == .orderedSame }?.name
            ?? snapshot.spaces.first?.name
            ?? "School"
    }

    /// Creates a class in `term`, returning it to the caller.
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

    /// Points a class at the syllabus document kept for it in the `syllabi` bucket (0044).
    /// Written only after the upload succeeded — a pointer to nothing is worse than none.
    func setSyllabusPath(projectID: UUID, path: String?) {
        guard var project = snapshot.projects.first(where: { $0.id == projectID }) else { return }
        project.syllabusPath = path
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

    // MARK: - A class's work

    /// This class's OPEN tasks, soonest deadline first (undated last). The one predicate
    /// the class row's count and the class page's Work list both read, so the badge can
    /// never disagree with what opening the class shows. `projectID` is authoritative;
    /// the name is the fallback for a task whose link predates the id column.
    func openWork(forClass klass: Project) -> [TaskItem] {
        snapshot.tasks
            .filter { task in
                guard !task.done else { return false }
                if let pid = task.projectID { return pid == klass.id }
                return !task.projectName.isEmpty
                    && task.projectName.caseInsensitiveCompare(klass.name) == .orderedSame
            }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return x != y ? x < y : a.title < b.title
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return a.title < b.title
                }
            }
    }
}
