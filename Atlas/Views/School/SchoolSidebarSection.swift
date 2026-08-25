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
    @State private var presentNewSemester = false
    @State private var presentCourseCatchUp = false
    /// The term the editor sheet is editing — drives the sheet directly, so it can never
    /// present with a stale (or missing) term.
    @State private var editingTerm: Term?

    private var term: Term? { state.displayedTerm }

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

                if !state.unlinkedCanvasCourses.isEmpty && term != nil {
                    let n = state.unlinkedCanvasCourses.count
                    promptRow(title: n == 1 ? "1 new course found" : "\(n) new courses found",
                              detail: "Canvas is sending items Atlas has no class for. Create them?") {
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
                Button("Add a class…") { presentWizard = true }
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
                Text(klass.name)
                    .atlasFont(size: 14, weight: selected ? .semibold : .regular, design: .rounded)
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
                if let code = klass.code, !code.isEmpty {
                    Text(code)
                        .atlasMono(size: 10, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .lineLimit(1)
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
            Button("Put this class away") {
                state.setClassArchived(projectID: klass.id, archived: true)
            }
        }
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
                Text("Set up your semester")
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
    private func promptRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
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
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}
