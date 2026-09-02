import SwiftUI
import AtlasCore

/// The School section of the sidebar — the visible face of the Phase 1 framework and,
/// per Phase 5, a top-level sibling of Dashboard / Calendar / Focus rather than a space.
///
/// Structure: a header carrying the active term (with the term switcher tucked behind
/// it), then that term's live classes. Soft-archived classes are hidden; the prompts
/// above the list are the framework's three "you have a decision to make" moments —
/// undated legacy classes, a finished term, and Canvas courses with no class yet.
struct SchoolSidebarSection: View {
    @EnvironmentObject var state: AppState

    /// Shared with `SidebarView` so every row kind — nav, space, project, class —
    /// hovers off one piece of state.
    @Binding var hovered: Route?

    @State private var presentWizard = false
    @State private var presentQuickAdd = false
    @State private var presentCanvasConnect = false
    @State private var confirmRemoveAll = false
    @State private var presentNewSemester = false
    @State private var presentCourseCatchUp = false
    /// Canvas course labels the catch-up prompt has already been dismissed for.
    @State private var dismissedCourses: Set<String> = CanvasCatchUpDismissals.labels
    /// The term the editor sheet is editing — drives the sheet directly, so it can never
    /// present with a stale (or missing) term.
    @State private var editingTerm: Term?
    /// The class whose color popover is open, anchored on its own row.
    @State private var recoloringClass: UUID?

    private var term: Term? { state.displayedTerm }

    /// Unlinked Canvas courses the sidebar prompt hasn't been dismissed for. Dismissing
    /// the card remembers the labels it was offering, so it stays away until Canvas sends
    /// a course Atlas has never offered before. Only this sidebar nudge is gated — School
    /// ⋯ → Connect Canvas still lists every unlinked course.
    private var undismissedCanvasCourses: [String] {
        state.unlinkedCanvasCourses.filter { !dismissedCourses.contains($0) }
    }

    /// The term's classes — or, with no term yet, the ones that predate the term model.
    /// Undated classes are shown, not prompted about: dates are optional now.
    private var termClasses: [Project] {
        guard let term else { return state.undatedClasses.sorted { $0.name < $1.name } }
        return state.classes(in: term).sorted { $0.name < $1.name }
    }

    /// A term whose end date has passed and that still has live classes — the moment to
    /// offer archiving. Never automatic: ending a semester is the user's call.
    private var finishedTerm: Term? {
        guard let term, let ends = term.endsOn,
              Calendar.current.startOfDay(for: ends) < Calendar.current.startOfDay(for: state.now),
              !termClasses.isEmpty else { return nil }
        return term
    }

    /// The Canvas feed's health (revoked/errored, stale, or ok), judged from whichever
    /// row the client has: `calendar_feeds` (multi-ICS) if deployed, else the older
    /// `canvas_connections` singleton. Nil when there's no Canvas feed at all — nothing
    /// to nudge about.
    private var canvasFeedHealth: CanvasFeedHealth? {
        if let feed = state.calendarFeeds.first(where: { $0.feedType == "canvas" }) {
            return CanvasFeedHealth.evaluate(status: feed.status, lastError: feed.lastError,
                                             lastSyncedAt: feed.lastSyncedDate, now: state.now)
        }
        guard let conn = state.canvasConnection else { return nil }
        return CanvasFeedHealth.evaluate(status: conn.status, lastError: conn.lastError,
                                         lastSyncedAt: conn.lastSyncedDate, now: state.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            if term == nil && termClasses.isEmpty {
                zeroState
            } else {
                if let finishedTerm {
                    promptRow(title: "\(finishedTerm.name) is over",
                              detail: "Put its \(termClasses.count == 1 ? "class" : "\(termClasses.count) classes") away. Nothing is deleted — notes and work stay searchable.") {
                        state.archiveClasses(in: finishedTerm)
                    }
                }

                if let health = canvasFeedHealth, health != .ok {
                    promptRow(title: "Canvas feed stopped syncing", detail: canvasFeedHealthDetail(health)) {
                        state.settingsSection = .calendars
                        state.route = .settings
                    }
                }

                if !undismissedCanvasCourses.isEmpty && term != nil {
                    let n = state.unlinkedCanvasCourses.count
                    promptRow(title: n == 1 ? "1 new course found" : "\(n) new courses found",
                              detail: "Canvas is sending items Atlas has no class for. Create them?",
                              onDismiss: {
                                  dismissedCourses = CanvasCatchUpDismissals.dismiss(state.unlinkedCanvasCourses)
                              }) {
                        presentCourseCatchUp = true
                    }
                }

                ForEach(termClasses) { klass in
                    classRow(klass)
                }

                if termClasses.isEmpty && term != nil {
                    addFirstClassRow
                }
            }
        }
        .sheet(isPresented: $presentWizard) {
            // With a semester already in place there's nothing to ask about being a
            // student — go straight to "how does your schedule exist?".
            SemesterWizard(startAt: term == nil ? .student : .door)
        }
        .sheet(isPresented: $presentQuickAdd) {
            QuickAddClassSheet(term: term)
        }
        .confirmationDialog("Remove every class in \(term?.name ?? "this semester")?",
                            isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove \(termClasses.count) \(termClasses.count == 1 ? "class" : "classes")",
                   role: .destructive) {
                state.removeAllClasses(in: term)
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            // Says exactly what goes, because a bad import is the reason anyone is here.
            Text("Their meeting times and this semester's key dates go with them; any work filed under them is unfiled, not deleted. "
                 + "Classes you already put away from an earlier semester are untouched. This can't be undone.")
        }
        .sheet(isPresented: $presentCanvasConnect) {
            SemesterWizard(startAt: .canvas)
        }
        .sheet(isPresented: $presentNewSemester) {
            NewSemesterSheet(previous: term)
        }
        .sheet(isPresented: $presentCourseCatchUp) {
            CanvasCourseChecklist(term: term, courses: state.unlinkedCanvasCourses)
        }
        .sheet(item: $editingTerm) { term in
            TermEditorSheet(term: term,
                            adoptUndatedClasses: state.unassignedClassesNeedTerm)
        }
    }

    // MARK: - Header

    /// "SCHOOL", the term stated quietly in mono, and an overflow menu. The term is
    /// reported, never asked about: with no term yet the label is simply absent — the
    /// section never says "No semester yet". Editing dates, switching terms and starting
    /// the next one all live behind the ellipsis, out of the way of the daily path.
    ///
    /// Layout: the caps label is `fixedSize`d so "SCHOOL" can never wrap to "SCHOO L",
    /// and the term label truncates instead of pushing the menu off the 232pt sidebar.
    private var header: some View {
        HStack(spacing: 6) {
            Text("SCHOOL")
                .atlasCapsLabel()
                .fixedSize()
            Spacer(minLength: 4)
            if let term {
                Text(term.name)
                    .atlasMono(size: 10, weight: .medium)
                    .textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // "+" adds ONE class by hand. The wizard is the semester-setup flow and lives
            // behind the zero state and the ⋯ menu — being asked "are you a student?"
            // again to add the class you forgot is not a quick add.
            Button { presentQuickAdd = true } label: {
                Image(systemName: "plus")
                    .atlasFont(size: 11, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a class")
            Menu {
                if let term {
                    Button("Edit \(term.name)…") { editingTerm = term }
                }
                let others = state.terms.filter { $0.id != term?.id }
                if !others.isEmpty {
                    Divider()
                    ForEach(others) { other in
                        Button(other.name) { state.schoolTermOverride = other.id }
                    }
                    if state.schoolTermOverride != nil {
                        Button("Back to now") { state.schoolTermOverride = nil }
                    }
                }
                Divider()
                Button("Start a new semester…") { presentNewSemester = true }
                Button("Add classes from a file or link…") { presentWizard = true }
                // Canvas carries the assignments, not the classes — so it lives here,
                // beside the class list it files work under, not as a door in the wizard.
                Button("Connect Canvas…") { presentCanvasConnect = true }
                if !termClasses.isEmpty {
                    Divider()
                    Button("Remove all classes…", role: .destructive) { confirmRemoveAll = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .atlasFont(size: 11, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Edit term dates, switch or start a semester")
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// The one-line reason under "Canvas feed stopped syncing" — `last_error` when the
    /// server sent one, else how long it's been since the last successful sync.
    private func canvasFeedHealthDetail(_ health: CanvasFeedHealth) -> String {
        switch health {
        case .ok:
            return ""
        case .broken(let reason):
            return reason ?? "Your Canvas feed link may have expired. Reconnect it in Settings."
        case .stale(let lastSyncedAt):
            guard let lastSyncedAt else { return "It hasn't synced yet." }
            let hours = max(1, Int(state.now.timeIntervalSince(lastSyncedAt) / 3600))
            return "Last synced \(hours) \(hours == 1 ? "hour" : "hours") ago."
        }
    }

    // MARK: - Rows

    /// A class row. Same geometry as `SidebarView.projectRow` (the class IS a project)
    /// with the course code trailing in mono — the one tell that this level is School.
    private func classRow(_ klass: Project) -> some View {
        let route = Route.project(klass.id)
        let selected = state.route == route
        return Button { state.route = route } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(klass.colorToken.map { ColorToken.color(for: $0) } ?? klass.spaceColor)
                    .frame(width: 8, height: 8)
                // "Introduction to Organic Chemistry II" has to survive a 232pt sidebar.
                // The name takes ALL the width the row has left (layoutPriority) so it
                // truncates only when it genuinely doesn't fit — middle, so the tail that
                // tells two sections of one class apart survives.
                Text(klass.name)
                    .atlasFont(size: 14, weight: selected ? .semibold : .regular, design: .rounded)
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                if let code = klass.code, !code.isEmpty {
                    Text(code)
                        .atlasMono(size: 10, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .rowChrome(selected: selected, hovered: hovered == route)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = route } else if hovered == route { hovered = nil }
        }
        .contextMenu {
            Button("Change color…") { recoloringClass = klass.id }
            Button("Put this class away") {
                state.setClassArchived(projectID: klass.id, archived: true)
            }
        }
        .popover(isPresented: Binding(get: { recoloringClass == klass.id },
                                      set: { if !$0 { recoloringClass = nil } }),
                 arrowEdge: .trailing) {
            colorPopover(klass)
        }
    }

    /// CLASS COLOR popover — the same chooser as the project page's dot button, so a
    /// class recolors identically whether you're in the sidebar or on its page.
    private func colorPopover(_ klass: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLASS COLOR").atlasCapsLabel()
            Button {
                state.setProjectColorToken(projectID: klass.id, token: nil)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(klass.spaceColor, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(AtlasTheme.Colors.textPrimary,
                                        lineWidth: klass.colorToken == nil ? 2.5 : 0)
                                .padding(-3)
                        )
                    Text("Inherit space color")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            AtlasColorGrid(selected: klass.colorToken.map { ColorToken.color(for: $0) }) { color in
                state.setProjectColorToken(projectID: klass.id,
                                           token: ColorToken.token(for: color))
            }
        }
        .padding(16)
    }

    private var addFirstClassRow: some View {
        Button { presentWizard = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.dotted").atlasFont(size: 12)
                Text("Add your first class").atlasFont(size: 13, design: .rounded)
                Spacer()
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The School zero state — the wizard, in place of the fake seeded class the server
    /// used to create.
    private var zeroState: some View {
        Button { presentWizard = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your classes")
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text("Your classes already exist somewhere — Canvas, your school's calendar. Bring them in once.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    /// A one-decision nudge above the class list. Same outlined card as the zero state,
    /// so School has exactly one prompt shape.
    /// `onDismiss`, when given, adds a small ✕ that puts the prompt away for good.
    private func promptRow(title: String, detail: String,
                           onDismiss: (() -> Void)? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(detail)
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .atlasFont(size: 8, weight: .semibold)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop asking about these courses")
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}

/// Which Canvas course labels the sidebar catch-up prompt has been dismissed for.
///
/// Device-local, like Atlas's other "don't show me this again" keys
/// (`checklist.dismissed`, `calendar.lateBar.dismissedOn`). Keyed by the Canvas course
/// label itself, so the prompt returns the moment a course Atlas has never offered
/// shows up — and never for the ones the user already waved off.
enum CanvasCatchUpDismissals {
    private static let key = "school.canvasCatchUp.dismissed"

    static var labels: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    /// Records `courses` as dismissed and hands back the updated set.
    static func dismiss(_ courses: [String]) -> Set<String> {
        let updated = labels.union(courses)
        UserDefaults.standard.set(updated.sorted(), forKey: key)
        return updated
    }
}
