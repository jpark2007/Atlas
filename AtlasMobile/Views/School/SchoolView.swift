import SwiftUI
import AtlasCore

/// The School tab — the phone's face of the Phase 1 framework, and the iOS counterpart
/// of the Mac's top-level School sidebar section.
///
/// Structure: a header carrying the active term (with the term switcher tucked behind it
/// as a menu, not a nav level), then that term's live classes, each pushing its class hub.
/// Soft-archived classes are hidden; the prompts above the list are the framework's three
/// "you have a decision to make" moments — undated legacy classes, a finished term, and
/// Canvas courses with no class yet.
struct SchoolView: View {
    @EnvironmentObject private var store: MobileStore

    /// Which term the list is showing when the user has looked away from "now". Session
    /// state, exactly like the Mac's `schoolTermOverride`.
    @State private var termOverride: UUID?

    @State private var presentWizard = false
    @State private var presentCourseCatchUp = false
    @State private var editingTerm: Term?
    @State private var showSettings = false

    private var term: Term? {
        if let id = termOverride, let t = store.terms.first(where: { $0.id == id }) { return t }
        return store.activeTerm
    }

    private var termClasses: [Project] {
        guard let term else { return [] }
        return store.classes(in: term).sorted { $0.name < $1.name }
    }

    /// A term whose end date has passed and that still has live classes — the moment to
    /// offer putting them away. Never automatic: ending a semester is the user's call.
    private var finishedTerm: Term? {
        guard let term, let ends = term.endsOn,
              Calendar.current.startOfDay(for: ends) < Calendar.current.startOfDay(for: Date()),
              !termClasses.isEmpty else { return nil }
        return term
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                termSwitcher
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                Rectangle().fill(MobileTheme.hairline).frame(height: 1)
                list
            }
            .background(MobileTheme.bg.ignoresSafeArea())
            .navigationDestination(for: UUID.self) { id in
                ClassHubView(classID: id).environmentObject(store)
            }
        }
        .sheet(isPresented: $presentWizard) {
            // With a semester already in place there's nothing to ask about being a
            // student — go straight to "how does your schedule exist?".
            SemesterWizardSheet(startAt: term == nil ? .student : .door).environmentObject(store)
        }
        .sheet(isPresented: $presentCourseCatchUp) {
            CanvasCourseChecklistSheet(term: term, courses: store.unlinkedCanvasCourses)
                .environmentObject(store)
        }
        .sheet(item: $editingTerm) { editing in
            TermEditorSheet(term: editing,
                            adoptUndatedClasses: store.unassignedClassesNeedTerm)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(store)
        }
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack {
            Text("School").edScreenTitle()
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MobileTheme.ink)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
    }

    /// The term name plus everything you can do to a semester. Switching semesters is
    /// rare, so it earns a menu tucked behind the header — never a nav level.
    private var termSwitcher: some View {
        Menu {
            if let term {
                Button("Edit \(term.name)…") { editingTerm = term }
            }
            let others = store.terms.filter { $0.id != term?.id }
            if !others.isEmpty {
                Divider()
                ForEach(others) { other in
                    Button(other.name) { termOverride = other.id }
                }
                if termOverride != nil {
                    Button("Back to now") { termOverride = nil }
                }
            }
            Divider()
            Button("Add a class…") { presentWizard = true }
        } label: {
            HStack(spacing: 5) {
                Text(term?.name ?? "No semester yet")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(MobileTheme.muted)
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.unassignedClassesNeedTerm {
                    promptCard(title: "Date your term",
                               detail: "You have classes from before Atlas had semesters. Name the term they belong to.") {
                        editingTerm = Term(name: suggestedTermName())
                    }
                }

                if term == nil && termClasses.isEmpty && !store.unassignedClassesNeedTerm {
                    zeroState
                } else {
                    if let finishedTerm {
                        promptCard(title: "\(finishedTerm.name) is over",
                                   detail: "Put its \(termClasses.count == 1 ? "class" : "\(termClasses.count) classes") away. Nothing is deleted — notes and work stay searchable.") {
                            store.archiveClasses(in: finishedTerm)
                        }
                    }

                    if !store.unlinkedCanvasCourses.isEmpty && term != nil {
                        let n = store.unlinkedCanvasCourses.count
                        promptCard(title: n == 1 ? "1 new course found" : "\(n) new courses found",
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
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 72)
        }
        .refreshable { await store.refresh() }
    }

    /// A class row: color dot, name, trailing course code — and its open-work count, the
    /// one thing a phone glance is actually for.
    private func classRow(_ klass: Project) -> some View {
        NavigationLink(value: klass.id) {
            HStack(spacing: 12) {
                Circle()
                    .fill(klass.colorToken.map { ColorToken.color(for: $0) } ?? klass.spaceColor)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(klass.name)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .lineLimit(1)
                    if let subtitle = subtitle(klass) {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.faint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let code = klass.code, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(MobileTheme.faint)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MobileTheme.faint)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .edHairlineBelow()
    }

    /// "MWF · 10 AM–10:50 AM" when the class has a schedule, else its open-work count,
    /// else nothing — never a placeholder that says the same as silence.
    private func subtitle(_ klass: Project) -> String? {
        if let first = klass.meetingPattern.first {
            return MeetingPatternFormat.describe(first)
        }
        let open = store.snapshot.tasks.filter {
            !$0.done && $0.projectName.caseInsensitiveCompare(klass.name) == .orderedSame
        }.count
        return open == 0 ? nil : "\(open) open"
    }

    private var addFirstClassRow: some View {
        Button { presentWizard = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.dotted").font(.system(size: 15, weight: .medium))
                Text("Add your first class")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(MobileTheme.muted)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The School zero state — the wizard, in place of the fake seeded class the server
    /// used to create.
    private var zeroState: some View {
        Button { presentWizard = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your semester")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Text("Your classes already exist somewhere — Canvas, your school's calendar. Bring them in once.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    /// A one-decision nudge above the class list. Same outlined card as the zero state,
    /// so School has exactly one prompt shape.
    private func promptCard(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }
}
