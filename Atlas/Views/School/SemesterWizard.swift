import SwiftUI
import AtlasCore
import UniformTypeIdentifiers

/// "Add your classes" — the School zero state, in place of the fake seeded class the
/// server used to create.
///
/// Order is the agreed one: *are you a student?* → **add your classes** (the doors,
/// school calendar link first) → done. The word "semester" never appears: the term is
/// created silently from today's date the moment a class exists (`AppState.ensureActiveTerm`)
/// and its dates stay editable from School → Edit term. The premise throughout is that
/// the schedule already exists somewhere and Atlas's job is to go get it, not to make the
/// student build a timetable by hand.
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
        case file           // a downloaded .ics file, imported once
    }

    /// Where the flow opens. The full run starts at "are you a student?"; adding a class
    /// to a semester that already exists skips straight to the doors.
    var startAt: Step = .student

    /// An `.ics` opened from Finder ("Open with Atlas") — read as soon as the sheet
    /// appears, so the file door opens already holding the file.
    var openedFile: URL?

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

    // Manual entry: a handful of name/code rows.
    @State private var manualRows: [ManualClass] = [ManualClass(), ManualClass(), ManualClass()]

    // File door: what the parsed .ics turned out to hold.
    @State private var fileCourses: [ICSFile.Course] = []
    @State private var fileChosen: Set<String> = []
    @State private var fileName: String?
    @State private var presentFileChooser = false
    @State private var dropTargeted = false

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
                    case .file:       fileStep
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
        .onAppear {
            step = startAt
            if let openedFile { load(openedFile) }
        }
        .fileImporter(isPresented: $presentFileChooser,
                      allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data]) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Add your classes")
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
                   "School in Atlas is your classes and the work that hangs off them.")
            choice("Yes — add my classes", "It takes about a minute.") { step = .door }
            choice("Not right now", "Hides the School section. Turn it back on in Settings → App & Help.") {
                state.schoolEnabled = false
                dismiss()
            }
        }
    }

    // MARK: - Step 2 · which door

    private var doorStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Add your classes",
                   "Wherever your schedule already lives, Atlas can read it — you shouldn't have to type it twice.")
            choice("My school publishes a calendar link",
                   "Your classes and their meeting times, in one link. A registrar or timetable feed ending in .ics.",
                   recommended: true) {
                step = .schoolLink
            }
            choice("I downloaded my schedule as a file",
                   "The .ics your school's \"export schedule\" button hands you. A link keeps itself updated; a file is a one-time import.") {
                step = .file
            }
            choice("I'll type my classes",
                   "Fastest if you only have a few. Scan a syllabus afterward to fill in times and policies.") {
                step = .manual
            }
            choice("Connect Canvas",
                   "Best for your assignments — they flow in automatically. Atlas finds your courses too; add times from your school calendar or a syllabus scan.") {
                step = .canvas
            }
            // The scan commits ONTO a class (times, info card, its work), so it needs one
            // to exist first — inside the wizard there is nothing to file it under yet.
            // Type the classes here, then scan each syllabus from its own page.
            disabledChoice("I have a screenshot or a PDF",
                           "Add the class first, then hit Scan a syllabus on its page — Atlas reads the times, the work and the policies off it.")
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

    // MARK: - Step 3c · a downloaded .ics file

    /// Door 1b. Same landing place as the link door — the class ends up knowing its
    /// meeting blocks — but read once, on this machine: there is no address to go back
    /// to, so no feed row is created and nothing re-syncs. That difference is the one
    /// line of copy in the prompt.
    @ViewBuilder
    private var fileStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt("Bring in your schedule file",
                   "A link keeps itself updated. A file is a one-time import — drop it in and Atlas reads the classes out of it.")

            if fileCourses.isEmpty {
                dropZone
            } else {
                if let fileName {
                    Text(fileName)
                        .atlasMono(size: 11, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(fileCourses) { course in
                        fileCourseRow(course)
                    }
                }
                actionButton(fileChosen.isEmpty
                             ? "Pick at least one"
                             : "Add \(fileChosen.count) \(fileChosen.count == 1 ? "class" : "classes")") {
                    createFromFile()
                }
            }

            backButton { step = .door }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .atlasFont(size: 22, weight: .light)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text("Drop your .ics file here")
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Button("Choose a file…") { presentFileChooser = true }
                .buttonStyle(.plain)
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(dropTargeted ? AtlasTheme.Colors.textPrimary.opacity(0.04) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.md, style: .continuous)
            .strokeBorder(dropTargeted ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.border,
                          style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in load(url) }
            }
            return true
        }
    }

    private func fileCourseRow(_ course: ICSFile.Course) -> some View {
        let picked = fileChosen.contains(course.id)
        return Button {
            if picked { fileChosen.remove(course.id) } else { fileChosen.insert(course.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: picked ? "checkmark.square.fill" : "square")
                    .atlasFont(size: 14)
                    .foregroundStyle(picked ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(course.name)
                            .atlasFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .lineLimit(1)
                        if let code = course.code {
                            Text(code).atlasMono(size: 10, weight: .medium)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                    // What Atlas will draw on the calendar, said out loud before it does it.
                    if !course.meetings.isEmpty {
                        Text(course.meetings.map(MeetingPatternFormat.describe).joined(separator: " · "))
                            .atlasFont(size: 11, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .atlasHairlineBelow()
    }

    // MARK: - Step 4 · waiting for the first sync

    private var importingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            prompt(importTimedOut ? "Nothing has arrived yet" : "Bringing your schedule in…",
                   importTimedOut
                   ? "Your first sync can take a few minutes. Atlas will offer to create the classes as soon as the courses land."
                   : "Atlas is reading the feed. This usually takes a moment.")
            if !importTimedOut { ProgressView().controlSize(.small) }
            actionButton("Done for now") { dismiss() }
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
                if !chosen.isEmpty {
                    state.createClasses(fromCanvasCourses: chosen, term: ensureTerm())
                }
                dismiss()
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

    private func choice(_ title: String, _ detail: String, recommended: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                if recommended {
                    Text("RECOMMENDED").atlasCapsLabel()
                }
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

    /// The term new classes go under. The wizard never mentions it: `ensureActiveTerm`
    /// makes one from today's date if there isn't one, and the dates stay editable from
    /// School → Edit term.
    private func ensureTerm() -> Term {
        if let term { return term }
        let resolved = state.ensureActiveTerm()
        term = resolved
        return resolved
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
                if type == "canvas" {
                    step = .importing
                } else {
                    // The feed's classes land as events; a term to hang them on so
                    // School opens on "add your first class", not the wizard again.
                    _ = ensureTerm()
                    dismiss()
                }
            } catch {
                self.error = "Couldn't connect that link. Check it and your connection, then try again."
            }
            working = false
        }
    }

    /// Reads a dropped or chosen `.ics` and shows what it holds. Nothing is created until
    /// the user confirms the list — a file the user picked is still a proposal.
    private func load(_ url: URL) {
        step = .file
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            error = "Couldn't read that file."
            return
        }
        let found = ICSFile.courses(in: raw)
        guard !found.isEmpty else {
            error = "Atlas didn't find any classes in that file. Check it's the schedule export and not an empty calendar."
            return
        }
        error = nil
        fileName = url.lastPathComponent
        fileCourses = found
        fileChosen = Set(found.map(\.id))
    }

    /// Creates the picked classes and gives each the meeting blocks the file described —
    /// the same place the link door lands, minus the feed.
    private func createFromFile() {
        let picked = fileCourses.filter { fileChosen.contains($0.id) }
        guard !picked.isEmpty else { return }
        let target = ensureTerm()
        for course in picked {
            guard let created = state.addClass(name: course.name, code: course.code, termID: target.id)
            else { continue }
            if !course.meetings.isEmpty {
                state.setMeetingPattern(projectID: created.id, blocks: course.meetings, meetingInfo: nil)
            }
        }
        dismiss()
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
        dismiss()
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
