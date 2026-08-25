import SwiftUI
import AtlasCore

/// "Set up your semester" on the phone — the whole of Enable School, completable here.
///
/// Same agreed order as the Mac: *are you a student?* → **how does your schedule already
/// exist?** → the chosen door → the courses Atlas found, as a checklist → term dates.
/// The premise throughout is that the schedule already exists somewhere and Atlas's job
/// is to go get it, not to make the student build a timetable by hand.
///
/// The Canvas copy is phone-appropriate: on a phone you tap, and Canvas's calendar feed
/// lives behind the desktop site, so the steps say so instead of pretending otherwise.
struct SemesterWizardSheet: View {
    @EnvironmentObject private var store: MobileStore
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

    @StateObject private var feeds = FeedService()
    @State private var feedURL = ""
    @State private var feedName = ""
    @State private var working = false
    @State private var error: String?
    /// True once the wait for the first sync has run its course with nothing found.
    @State private var importTimedOut = false
    @State private var presentTermEditor = false

    @State private var manualRows: [ManualClass] = [ManualClass(), ManualClass(), ManualClass()]

    struct ManualClass: Identifiable {
        let id = UUID()
        var name = ""
        var code = ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
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
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { step = startAt }
        .sheet(isPresented: $presentTermEditor) {
            if let term {
                TermEditorSheet(term: term) { _ in dismiss() }
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Text("Set up your semester").edScreenTitle()
            Spacer(minLength: 12)
            Button { dismiss() } label: { Text("Close").edCapsLabel() }
                .buttonStyle(.plain)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Step 1 · are you a student?

    @ViewBuilder
    private var studentStep: some View {
        prompt("Are you a student?",
               "School in Atlas is a semester, your classes, and the work that hangs off them.")
        choice("Yes — set up my classes", "It takes about a minute.") { step = .door }
        choice("Not right now", "Hides the School tab. Turn it back on in Settings → App & Help.") {
            store.schoolEnabled = false
            dismiss()
        }
    }

    // MARK: - Step 2 · which door

    @ViewBuilder
    private var doorStep: some View {
        prompt("How does your schedule already exist?",
               "Wherever it lives, Atlas can read it — you shouldn't have to type it twice.")
        choice("It's in Canvas", "Assignments and class events, straight from your course feed.") {
            step = .canvas
        }
        choice("My school publishes a calendar link", "A registrar or timetable feed ending in .ics.") {
            step = .schoolLink
        }
        choice("I'll type my classes", "Fastest if you only have a few.") { step = .manual }
        // The scan commits ONTO a class (times, info card, its work), so it needs one to
        // exist first — inside the wizard there is nothing to file it under yet.
        disabledChoice("I have a photo of my syllabus",
                       "Add the class first, then tap Scan a syllabus on its page — Atlas reads the times, the work and the policies off it.")
    }

    // MARK: - Step 3a · Canvas

    @ViewBuilder
    private var canvasStep: some View {
        prompt("Copy your Canvas calendar link",
               "Canvas keeps it behind one screen. Once Atlas has it, it stays up to date on its own.")
        VStack(alignment: .leading, spacing: 10) {
            instruction(1, "Open Canvas in Safari and tap Calendar.")
            instruction(2, "Tap Calendar Feed at the bottom of the page. On a phone you may need Request Desktop Website first.")
            instruction(3, "Press and hold the link that appears, then Copy — it ends in .ics.")
        }
        .padding(.bottom, 20)
        linkField("https://school.instructure.com/feeds/calendars/….ics", text: $feedURL)
        actionButton(working ? "Connecting…" : "Bring in my Canvas") { connect(type: "canvas") }
        backButton { step = .door }
    }

    // MARK: - Step 3b · school calendar link

    @ViewBuilder
    private var schoolLinkStep: some View {
        prompt("Paste your school's calendar link",
               "A registrar or timetable feed. Atlas shows those events; it never edits them.")
        plainField("Name it (e.g. Registrar)", text: $feedName)
        linkField("https://….ics", text: $feedURL)
        actionButton(working ? "Connecting…" : "Add this calendar") { connect(type: "ics") }
        backButton { step = .door }
    }

    // MARK: - Step 4 · waiting for the first sync

    private var importingStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            prompt(importTimedOut ? "Nothing has arrived yet" : "Bringing your schedule in…",
                   importTimedOut
                   ? "Your first sync can take a few minutes. Name your semester now — Atlas will offer to create the classes as soon as the courses land."
                   : "Atlas is reading the feed. This usually takes a moment.")
            if !importTimedOut {
                ProgressView().tint(MobileTheme.muted).padding(.bottom, 8)
            }
            actionButton("Name my semester") { goToTerm() }
        }
        .task(id: importTimedOut) {
            guard !importTimedOut else { return }
            // Server-side sync writes the items; a re-pull is the only way the client
            // learns about them.
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                await store.refresh()
                if !store.unlinkedCanvasCourses.isEmpty {
                    step = .courses
                    return
                }
            }
            importTimedOut = true
        }
    }

    // MARK: - Step 5 · the courses Atlas found

    @ViewBuilder
    private var coursesStep: some View {
        prompt("Atlas found your courses",
               "Pick the ones to keep as classes. Their Canvas work files under them from now on.")
        CanvasCourseChecklistBody(courses: store.unlinkedCanvasCourses) { chosen in
            let target = ensureTerm()
            store.createClasses(fromCanvasCourses: chosen, term: target)
            goToTerm()
        }
    }

    // MARK: - Step 6 · manual

    @ViewBuilder
    private var manualStep: some View {
        prompt("What are you taking?",
               "Name and course code. You can add meeting times on each class afterwards.")
        ForEach($manualRows) { $row in
            VStack(alignment: .leading, spacing: 8) {
                TextField("Organic Chemistry", text: $row.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .tint(MobileTheme.accent)
                TextField("CHEM 201", text: $row.code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .tint(MobileTheme.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
            .padding(.vertical, 12)
            .edHairlineBelow()
        }
        Button { manualRows.append(ManualClass()) } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                Text("One more").font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(MobileTheme.accentText)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        actionButton("Create these classes") { createManual() }
        backButton { step = .door }
    }

    // MARK: - Step 7 · term dates

    @ViewBuilder
    private var termStep: some View {
        prompt("Last thing — name your semester",
               "Dates keep class meetings inside the term, and breaks stop them.")
        actionButton("Name my semester") { presentTermEditor = true }
        Button("I'll do it later") { dismiss() }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
    }

    // MARK: - Pieces

    private func prompt(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 20)
    }

    private func choice(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    /// Door 3. Shown, not offered — the syllabus scan lands on the class page, and saying
    /// so is better than pretending the door isn't there.
    private func disabledChoice(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.faint)
            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
            .strokeBorder(MobileTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(MobileTheme.faint)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plainField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 15.5, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .padding(.vertical, 12)
            .edHairlineBelow()
            .padding(.bottom, 16)
    }

    private func linkField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .padding(.vertical, 12)
            .edHairlineBelow()
            .padding(.bottom, 20)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity)
                .edOutlineControl()
        }
        .buttonStyle(.plain)
        .disabled(working)
        .padding(.top, 8)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Back").edCapsLabel().frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    // MARK: - Actions

    /// The term new classes go under: the one this wizard already made, else the active
    /// one, else a freshly named term. Created before any class so nothing lands undated.
    private func ensureTerm() -> Term {
        if let term { return term }
        if let active = store.activeTerm { term = active; return active }
        let created = Term(name: suggestedTermName())
        store.saveTerm(created)
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
        if type == "canvas", !CanvasService.isValidFeedURL(url) {
            error = "That doesn't look like a Canvas feed link. It's under Canvas → Calendar → Calendar Feed."
            return
        }
        if type == "ics", !FeedService.isValidICSURL(url) {
            error = "That doesn't look like a calendar link. It should start with https and usually ends in .ics."
            return
        }
        error = nil
        working = true
        let displayName = type == "canvas"
            ? "Canvas"
            : (feedName.trimmingCharacters(in: .whitespaces).isEmpty ? "School calendar" : feedName)
        Task {
            guard let jwt = await store.validAccessToken() else {
                error = "Sign in to Atlas first."
                working = false
                return
            }
            do {
                try await feeds.connect(feedUrl: url, feedType: type, displayName: displayName,
                                        spaceName: store.schoolSpaceName(), jwt: jwt)
                AtlasTips.ConnectSource.hasConnection = true
                UserDefaults.standard.set(true, forKey: "checklist.connected")
                feedURL = ""   // don't retain the capability URL in the field
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
            store.addClass(name: row.name.trimmingCharacters(in: .whitespaces),
                           code: code.isEmpty ? nil : code,
                           termID: target.id)
        }
        MobileTheme.Haptic.success()
        step = .term
    }
}
