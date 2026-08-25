import SwiftUI
import AtlasCore

/// "Set up your semester" — the School zero state, in place of the fake seeded class
/// the server used to create.
///
/// Order is the agreed one: *are you a student?* → **how does your schedule already
/// exist?** → the chosen door → the courses Atlas found, as a checklist → term dates.
/// The premise throughout is that the schedule already exists somewhere and Atlas's job
/// is to go get it, not to make the student build a timetable by hand.
struct SemesterWizard: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var feeds: FeedService
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case student        // are you a student?
        case door           // how does your schedule already exist?
        case canvas         // copy your Canvas calendar link
        case importing      // the feed is connected; waiting for the first sync
        case courses        // "create these as classes?"
        case manual         // type the classes
        case schoolLink     // a calendar link from the school/registrar
        case term           // name + dates + key dates
    }

    /// Where the flow opens. The full run starts at "are you a student?"; adding a class
    /// to a semester that already exists skips straight to the doors.
    var startAt: Step = .student

    @State private var step: Step = .student
    /// The term the wizard builds classes under — created (or reused) before any class is.
    @State private var term: Term?

    // Canvas / school-link connect state (mirrors Settings' connect forms).
    @State private var feedURL = ""
    @State private var feedName = ""
    @State private var working = false
    @State private var error: String?
    /// True once the wait for the first sync has run its course with nothing found.
    @State private var importTimedOut = false
    /// Drives the term editor the last step opens.
    @State private var presentTermEditor = false

    // Manual entry: a handful of name/code rows.
    @State private var manualRows: [ManualClass] = [ManualClass(), ManualClass(), ManualClass()]

    struct ManualClass: Identifiable {
        let id = UUID()
        var name = ""
        var code = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .student:    studentStep
                    case .door:       doorStep
                    case .canvas:     canvasStep
                    case .importing:  importingStep
                    case .courses:    coursesStep
                    case .manual:     manualStep
                    case .schoolLink: schoolLinkStep
                    case .term:       termStep
                    }
                    if let error {
                        Text(error)
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.danger)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 520, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { step = startAt }
        .sheet(isPresented: $presentTermEditor) {
            if let term {
                TermEditorSheet(term: term) { _ in dismiss() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Set up your semester")
                .atlasFont(size: 19, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    // MARK: - Step 1 · are you a student?

    private var studentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Are you a student?",
                   "School in Atlas is a semester, your classes, and the work that hangs off them.")
            choice("Yes — set up my classes", "It takes about a minute.") { step = .door }
            choice("Not right now", "Hides the School section. Turn it back on in Settings → App & Help.") {
                state.schoolEnabled = false
                dismiss()
            }
        }
    }

    // MARK: - Step 2 · which door

    private var doorStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("How does your schedule already exist?",
                   "Wherever it lives, Atlas can read it — you shouldn't have to type it twice.")
            choice("It's in Canvas", "Assignments and class events, straight from your course feed.") {
                step = .canvas
            }
            choice("My school publishes a calendar link", "A registrar or timetable feed ending in .ics.") {
                step = .schoolLink
            }
            choice("I'll type my classes", "Fastest if you only have a few.") { step = .manual }
            disabledChoice("I have a screenshot or a PDF",
                           "Coming with syllabus scan — Atlas will read the schedule off it.")
        }
    }

    // MARK: - Step 3a · Canvas

    private var canvasStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Copy your Canvas calendar link",
                   "Canvas keeps it behind one screen. Once Atlas has it, it stays up to date on its own.")
            VStack(alignment: .leading, spacing: 6) {
                instruction(1, "Open Canvas and click Calendar in the left menu.")
                instruction(2, "Scroll down the right-hand column and click Calendar Feed.")
                instruction(3, "Copy the whole link that appears — it ends in .ics.")
            }
            TextField("https://school.instructure.com/feeds/calendars/….ics", text: $feedURL)
                .textFieldStyle(.plain)
                .atlasFont(size: 13, design: .rounded)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            actionButton(working ? "Connecting…" : "Bring in my Canvas") { connect(type: "canvas") }
            backButton { step = .door }
        }
    }

    // MARK: - Step 3b · school calendar link

    private var schoolLinkStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Paste your school's calendar link",
                   "A registrar or timetable feed. Atlas shows those events; it never edits them.")
            TextField("Name it (e.g. Registrar)", text: $feedName)
                .textFieldStyle(.plain)
                .atlasFont(size: 13, design: .rounded)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            TextField("https://….ics", text: $feedURL)
                .textFieldStyle(.plain)
                .atlasFont(size: 13, design: .rounded)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            actionButton(working ? "Connecting…" : "Add this calendar") { connect(type: "ics") }
            backButton { step = .door }
        }
    }

    // MARK: - Step 4 · waiting for the first sync

    private var importingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt(importTimedOut ? "Nothing has arrived yet" : "Bringing your schedule in…",
                   importTimedOut
                   ? "Your first sync can take a few minutes. Name your semester now — Atlas will offer to create the classes as soon as the courses land."
                   : "Atlas is reading the feed. This usually takes a moment.")
            if !importTimedOut { ProgressView().controlSize(.small) }
            actionButton("Name my semester") { goToTerm() }
        }
        .task(id: importTimedOut) {
            guard !importTimedOut else { return }
            // Poll the feed for courses. Server-side sync writes the items; a re-pull is
            // the only way the client learns about them.
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                await state.refreshFromServer()
                if !state.unlinkedCanvasCourses.isEmpty {
                    step = .courses
                    return
                }
            }
            importTimedOut = true
        }
    }

    // MARK: - Step 5 · the courses Atlas found

    private var coursesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Atlas found your courses",
                   "Pick the ones to keep as classes. Their Canvas work files under them from now on.")
            CanvasCourseChecklistBody(courses: state.unlinkedCanvasCourses) { chosen in
                let target = ensureTerm()
                state.createClasses(fromCanvasCourses: chosen, term: target)
                goToTerm()
            }
        }
    }

    // MARK: - Step 6 · manual

    private var manualStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("What are you taking?",
                   "Name and course code. You can add meeting times on each class afterwards.")
            ForEach($manualRows) { $row in
                HStack(spacing: 8) {
                    TextField("Organic Chemistry", text: $row.name)
                        .textFieldStyle(.plain)
                        .atlasFont(size: 13, design: .rounded)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                    TextField("CHEM 201", text: $row.code)
                        .textFieldStyle(.plain)
                        .atlasFont(size: 13, design: .rounded)
                        .frame(width: 110)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                }
            }
            Button { manualRows.append(ManualClass()) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").atlasFont(size: 10, weight: .semibold)
                    Text("One more").atlasFont(size: 12, weight: .semibold, design: .rounded)
                }
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            actionButton("Create these classes") { createManual() }
            backButton { step = .door }
        }
    }

    // MARK: - Step 7 · term dates

    private var termStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Last thing — name your semester",
                   "Dates keep class meetings inside the term, and breaks stop them.")
            actionButton("Name my semester") { presentTermEditor = true }
            Button("I'll do it later") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    // MARK: - Pieces

    private func prompt(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .atlasTitleSerif(size: 20)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text(detail)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(detail)
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.md, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Door 3. Shown, not offered — the screenshot scan lands with the syllabus scan, and
    /// saying so is better than pretending the door isn't there.
    private func disabledChoice(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(detail)
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.md, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").atlasMono(size: 11, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Back")
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// The term new classes go under: the one this wizard already made, else the active
    /// one, else a freshly named term. Created before any class so nothing lands undated.
    private func ensureTerm() -> Term {
        if let term { return term }
        if let active = state.activeTerm { term = active; return active }
        let created = Term(name: suggestedTermName())
        state.saveTerm(created)
        term = created
        return created
    }

    private func goToTerm() {
        _ = ensureTerm()
        step = .term
        presentTermEditor = true
    }

    private func connect(type: String) {
        let url = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == "canvas", !AtlasCore.CanvasService.isValidFeedURL(url) {
            error = "That doesn't look like a Canvas feed link. It's under Canvas → Calendar → Calendar Feed."
            return
        }
        if type == "ics", !FeedService.isValidICSURL(url) {
            error = "That doesn't look like a calendar link. It should start with https and usually ends in .ics."
            return
        }
        guard let jwt = auth.session?.accessToken else {
            error = "Sign in to Atlas first."
            return
        }
        error = nil
        working = true
        let displayName = type == "canvas"
            ? "Canvas"
            : (feedName.trimmingCharacters(in: .whitespaces).isEmpty ? "School calendar" : feedName)
        Task {
            do {
                try await feeds.connect(feedUrl: url, feedType: type, displayName: displayName,
                                        spaceName: state.schoolSpaceName(), jwt: jwt)
                await state.refreshCalendarFeeds()
                AtlasTips.ConnectSource.hasConnection = true
                feedURL = ""
                step = type == "canvas" ? .importing : .term
                if type != "canvas" { _ = ensureTerm() }
            } catch {
                self.error = "Couldn't connect that link. Check it and your connection, then try again."
            }
            working = false
        }
    }

    private func createManual() {
        let target = ensureTerm()
        let rows = manualRows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else {
            error = "Add at least one class."
            return
        }
        error = nil
        for row in rows {
            let code = row.code.trimmingCharacters(in: .whitespaces)
            state.addClass(name: row.name.trimmingCharacters(in: .whitespaces),
                           code: code.isEmpty ? nil : code,
                           termID: target.id)
        }
        step = .term
    }

    private func suggestedTermName() -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: Date())
        let year = cal.component(.year, from: Date())
        switch month {
        case 1...5: return "Spring \(year)"
        case 6...7: return "Summer \(year)"
        default:    return "Fall \(year)"
        }
    }
}

/// The checklist body without its own sheet chrome, so the wizard can host it inline and
/// the School section can host it in a sheet — one list, one behaviour.
struct CanvasCourseChecklistBody: View {
    let courses: [String]
    let onConfirm: ([String]) -> Void

    @State private var selected: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(courses, id: \.self) { course in
                Button {
                    if selected.contains(course) { selected.remove(course) } else { selected.insert(course) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.contains(course) ? "checkmark.square.fill" : "square")
                            .atlasFont(size: 14)
                            .foregroundStyle(selected.contains(course)
                                             ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
                        Text(course)
                            .atlasFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .atlasHairlineBelow()
            }

            Button { onConfirm(courses.filter { selected.contains($0) }) } label: {
                Text(selected.isEmpty ? "Skip for now" : "Create \(selected.count) \(selected.count == 1 ? "class" : "classes")")
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                        .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selected = Set(courses)
        }
    }
}
