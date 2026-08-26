import SwiftUI
import AtlasCore

/// "Set up your semester" on the phone — the whole of Enable School, completable here.
///
/// Same agreed order as the Mac: *are you a student?* → **add your classes** (the doors,
/// school calendar link first) → done. Classes are the point; term dates are optional and
/// never gate — an undated term is created silently, and dates can be filled in later
/// from School → Edit term. The premise throughout is that the schedule already exists
/// somewhere and Atlas's job is to go get it, not to make the student build a timetable
/// by hand.
///
/// Canvas is a Mac-only setup step: there is no connect flow here. Coursework Canvas
/// already synced still shows everywhere on the phone.
struct SemesterWizardSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case student        // are you a student?
        case door           // how does your schedule already exist?
        case manual         // type the classes
        case schoolLink     // a calendar link from the school/registrar
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
                case .manual:     manualStep
                case .schoolLink: schoolLinkStep
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Text("Add your classes").edScreenTitle()
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
        choice("Not right now", "Hides School. Turn it back on in Settings → App & Help.") {
            store.schoolEnabled = false
            dismiss()
        }
    }

    // MARK: - Step 2 · which door

    @ViewBuilder
    private var doorStep: some View {
        prompt("Add your classes",
               "Wherever your schedule already lives, Atlas can read it — you shouldn't have to type it twice.")
        choice("My school publishes a calendar link",
               "Your classes and their meeting times, in one link. A registrar or timetable feed ending in .ics.",
               recommended: true) {
            step = .schoolLink
        }
        choice("I'll type my classes",
               "Fastest if you only have a few. Scan a syllabus afterward to fill in times and policies.") {
            step = .manual
        }
        // The scan commits ONTO a class (times, info card, its work), so it needs one to
        // exist first — inside the wizard there is nothing to file it under yet.
        disabledChoice("I have a photo of my syllabus",
                       "Add the class first, then tap Scan a syllabus on its page — Atlas reads the times, the work and the policies off it.")
    }

    // MARK: - Step 3 · school calendar link

    @ViewBuilder
    private var schoolLinkStep: some View {
        prompt("Paste your school's calendar link",
               "A registrar or timetable feed. Atlas shows those events; it never edits them.")
        plainField("Name it (e.g. Registrar)", text: $feedName)
        linkField("https://….ics", text: $feedURL)
        actionButton(working ? "Connecting…" : "Add this calendar") { connect() }
        backButton { step = .door }
    }

    // MARK: - Step 4 · manual

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
        Text("If your school gives you a calendar file to download, import it on the Mac app.")
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
        backButton { step = .door }
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

    private func choice(_ title: String, _ detail: String, recommended: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                if recommended {
                    Text("Recommended").edCapsLabel()
                }
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
    /// one, else a freshly named undated one ("Fall 2026"). Created silently, and only
    /// when there are classes to hang on it — dates come later from School → Edit term.
    private func ensureTerm() -> Term {
        if let term { return term }
        if let active = store.activeTerm { term = active; return active }
        let created = Term(name: suggestedTermName())
        store.saveTerm(created)
        term = created
        return created
    }

    private func connect() {
        let url = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !FeedService.isValidICSURL(url) {
            error = "That doesn't look like a calendar link. It should start with https and usually ends in .ics."
            return
        }
        error = nil
        working = true
        let displayName = feedName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "School calendar" : feedName
        Task {
            guard let jwt = await store.validAccessToken() else {
                error = "Sign in to Atlas first."
                working = false
                return
            }
            do {
                try await feeds.connect(feedUrl: url, feedType: "ics", displayName: displayName,
                                        spaceName: store.schoolSpaceName(), jwt: jwt)
                AtlasTips.ConnectSource.hasConnection = true
                UserDefaults.standard.set(true, forKey: "checklist.connected")
                feedURL = ""   // don't retain the capability URL in the field
                // The feed's classes land as events; a term to hang them on so
                // School opens on "add your first class", not the wizard again.
                _ = ensureTerm()
                dismiss()
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
        dismiss()
    }
}
