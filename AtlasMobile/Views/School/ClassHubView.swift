import SwiftUI
import AtlasCore

/// One class, on the phone: the term chip, when and where it meets, who teaches it, the
/// syllabus "Class info" card, then its work and its notes.
///
/// On the Mac these last two are the ordinary project sections of the class page; the
/// phone has no project page, so the hub carries them — same content, one screen.
struct ClassHubView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let classID: UUID

    @State private var presentMeetingEditor = false
    @State private var presentSyllabusScan = false
    @State private var presentClassInfo = false
    @State private var presentClassInfoEditing = false
    @State private var presentSyllabusFile = false
    @State private var editingNote: Note?
    @State private var detail: ItemDetailSheet.Detail?
    @State private var showArchiveConfirm = false
    @State private var showAllWeights = false
    /// Which month folds of the Work list are open, keyed by the month's first instant,
    /// plus the undated tail. Both start closed, and both are this screen's alone.
    @State private var openMonths: Set<Date> = []
    @State private var showUndated = false
    /// One "now" for the whole render, so a bucket and its month fold can't straddle
    /// midnight and disagree.
    private let now = Date()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let weightPreview = 4
    private static let policyPreview = 3

    /// Read live from the snapshot so an edit made in a sheet is reflected on return.
    private var project: Project? {
        store.snapshot.projects.first { $0.id == classID }
    }

    private var term: Term? {
        project?.termID.flatMap { id in store.terms.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                // The class was archived or deleted from under us — say so rather than
                // rendering an empty shell.
                Text("This class isn't here anymore.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .navigationTitle(project?.name ?? "Class")
        .navigationBarTitleDisplayMode(.inline)
        // Tasks draws its own title row and hides the bar on the stack's ROOT; a pushed
        // page has to ask for it back or it arrives with no title and no back button.
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Scan a syllabus or schedule") { presentSyllabusScan = true }
                    if project?.syllabusPath != nil {
                        Button("View syllabus") { presentSyllabusFile = true }
                    }
                    Button("Edit class info") { openClassInfo(editing: true) }
                    Button(project?.meetingPattern.isEmpty == false ? "Edit meeting times" : "Add meeting times") {
                        presentMeetingEditor = true
                    }
                    Button("Put this class away", role: .destructive) { showArchiveConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
        }
        .sheet(isPresented: $presentMeetingEditor) {
            if let project {
                MeetingPatternSheet(project: project).environmentObject(store)
            }
        }
        .sheet(isPresented: $presentSyllabusScan) {
            if let project {
                SyllabusScanSheet(project: project).environmentObject(store)
            }
        }
        .sheet(isPresented: $presentClassInfo) {
            if let project {
                ClassInfoSheet(project: project, startEditing: presentClassInfoEditing)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $presentSyllabusFile) {
            if let project {
                SyllabusPreviewSheet(project: project).environmentObject(store)
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(note: note).environmentObject(store)
        }
        .sheet(item: $detail) { detail in
            ItemDetailSheet(detail: detail).environmentObject(store)
        }
        .confirmationDialog("Put this class away?", isPresented: $showArchiveConfirm, titleVisibility: .visible) {
            Button("Put it away", role: .destructive) {
                store.setClassArchived(projectID: classID, archived: true)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It leaves the class list. Nothing is deleted — its notes and work stay searchable.")
        }
    }

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chips(project)
                meetingBlock(project)
                classInfoBlock(project)
                workBlock(project)
                notesBlock(project)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 72)
        }
        .refreshable { await store.refresh() }
    }

    // MARK: - Chips

    private func chips(_ project: Project) -> some View {
        HStack(spacing: 8) {
            if let term {
                chip(term.name, color: MobileTheme.muted)
            } else {
                // A class with no term is the migration case — say so instead of hiding it.
                chip("No semester", color: MobileTheme.warning)
            }
            if let code = project.code, !code.isEmpty {
                chip(code, color: MobileTheme.faint)
            }
            if project.archivedAt != nil {
                chip("Put away", color: MobileTheme.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Meetings

    private func meetingBlock(_ project: Project) -> some View {
        section("Meets", action: (project.meetingPattern.isEmpty ? "Add times" : "Edit",
                                 { presentMeetingEditor = true })) {
            if project.meetingPattern.isEmpty {
                Text("Atlas doesn't know when this class meets, so it isn't on your calendar yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(project.meetingPattern.enumerated()), id: \.offset) { _, block in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 12, weight: .medium))
                        Text(MeetingPatternFormat.describe(block))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        if let location = block.location, !location.isEmpty {
                            Text("· \(location)")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(MobileTheme.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(MobileTheme.muted)
                }
                // Said only where it changes what a scan may do to this schedule (0050).
                if project.meetingPatternSource == .ics {
                    Text("From your imported schedule — locked")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
            }
            if let instructor = project.instructor, !instructor.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person").font(.system(size: 12, weight: .medium))
                    Text(instructor).font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MobileTheme.muted)
            }
            if let note = project.meetingInfo, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Class info card

    @ViewBuilder
    private func classInfoBlock(_ project: Project) -> some View {
        if let info = project.classInfo, !SyllabusDraft.isEmpty(info) {
            section("Class info", action: ("Edit", { openClassInfo(editing: true) })) {
                // Grading and policies are two different questions, so they get two
                // cards rather than one block. The phone stacks them; an iPad in a
                // regular width sets them side by side, as the Mac does.
                VStack(alignment: .leading, spacing: 14) {
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            if !info.gradeWeights.isEmpty {
                                gradingColumn(info.gradeWeights).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !info.policies.isEmpty {
                                policiesColumn(info.policies).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        if !info.gradeWeights.isEmpty { gradingColumn(info.gradeWeights) }
                        if !info.policies.isEmpty { policiesColumn(info.policies) }
                    }
                    if let hours = info.officeHours, !hours.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Office hours").edCapsLabel()
                            Text(hours)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(MobileTheme.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            section("Class info", action: nil) {
                Text("Scan your syllabus to fill this in — grade weights, late policy, office hours.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { presentSyllabusScan = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder").font(.system(size: 14, weight: .semibold))
                        Text("Scan a syllabus").font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                        .strokeBorder(MobileTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                // No syllabus to hand is not a reason to have no card.
                Button { openClassInfo(editing: true) } label: {
                    Text("Write it in yourself")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.accentText)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
    }

    private func openClassInfo(editing: Bool) {
        presentClassInfoEditing = editing
        presentClassInfo = true
    }

    /// Static syllabus facts, in the syllabus's own words. Explicitly NOT grade tracking:
    /// nothing here is computed, and Atlas never asks what you scored.
    private func gradingColumn(_ allWeights: [String]) -> some View {
        // The syllabus's own "Total: 100%" line is not a weight — the header computes
        // the total, so showing it again both misleads and double-counts.
        let weights = ClassInfoFormat.weightRows(allWeights)
        let visible = showAllWeights ? weights : Array(weights.prefix(ClassHubView.weightPreview))
        return VStack(alignment: .leading, spacing: 0) {
            infoColumnHeader("Grading", trailing: ClassInfoFormat.weightTotal(weights))
            VStack(spacing: 7) {
                ForEach(visible, id: \.self) { line in
                    let parts = ClassInfoFormat.weight(line)
                    HStack(spacing: 8) {
                        Text(parts.label)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if let percent = parts.percent {
                            Text(percent)
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MobileTheme.ink)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                        .strokeBorder(MobileTheme.hairline, lineWidth: 1))
                }
            }
            .padding(.top, 10)

            if weights.count > ClassHubView.weightPreview {
                quietButton(showAllWeights ? "Show fewer" : "All \(weights.count)") {
                    MobileTheme.Haptic.tap()
                    showAllWeights.toggle()
                }
            }
        }
    }

    private func policiesColumn(_ policies: [String]) -> some View {
        let visible = Array(policies.prefix(ClassHubView.policyPreview))
        return VStack(alignment: .leading, spacing: 0) {
            infoColumnHeader("Policies", trailing: "\(policies.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, line in
                    let parts = ClassInfoFormat.policy(line)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let title = parts.title {
                            Text(title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(MobileTheme.ink)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        // One line here; the sheet behind "Read all" carries the wording.
                        Text(parts.body)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)

                    if index < visible.count - 1 {
                        Rectangle().fill(MobileTheme.hairline).frame(height: 1)
                    }
                }
            }
            .padding(.top, 2)

            quietButton(policies.count > visible.count ? "Read all \(policies.count)" : "Read all") {
                openClassInfo(editing: false)
            }
        }
    }

    private func infoColumnHeader(_ title: String, trailing: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.faint)
                }
            }
            .padding(.bottom, 8)
            Rectangle().fill(MobileTheme.ink).frame(height: MobileTheme.rule)
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .overlay(Capsule().strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    // MARK: - Work

    /// The term, folded the way the Mac folds it: what's late, what's due this week, then
    /// the rest of the semester as one closed row per month. A full course is 60 items —
    /// a flat list of them is the density problem, not the answer. Bucketing comes from
    /// `TermTimeline` so the phone and the Mac can never disagree about "this week".
    private func workBlock(_ project: Project) -> some View {
        let tasks = store.openWork(forClass: project)
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A row checked off a moment ago has to hold its place in the bucket while it
        // lingers, and `TermTimeline.entries` drops done work — so it is bucketed as
        // still-open. The row itself reads `byID`, i.e. the real (done) task, and so
        // renders the struck-through state before sliding out.
        let bucketed = tasks.map { t -> TaskItem in
            guard t.done else { return t }
            var open = t; open.done = false; return open
        }
        let horizons = TermTimeline.byWeekHorizon(entries: TermTimeline.entries(tasks: bucketed, events: []), now: now)
        func bucket(_ h: TimeModel.WeekHorizon) -> [TermTimeline.Entry] { horizons[h] ?? [] }
        // With nothing due this week, next week gets its own open section instead of
        // hiding inside a month fold — and then it leaves the folds, never listed twice.
        let showsNextWeek = bucket(.thisWeek).isEmpty && !bucket(.nextWeek).isEmpty
        let months = TermTimeline.byMonth(
            entries: (showsNextWeek ? [] : bucket(.nextWeek)) + bucket(.later))

        return section("Work", action: nil) {
            if tasks.isEmpty {
                Text("Nothing due yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
            } else {
                if !bucket(.overdue).isEmpty {
                    workHeader("Overdue", count: bucket(.overdue).count, late: true)
                    workRows(bucket(.overdue), byID: byID)
                }
                if !bucket(.thisWeek).isEmpty {
                    workHeader("This week", count: bucket(.thisWeek).count)
                    workRows(bucket(.thisWeek), byID: byID)
                } else if bucket(.overdue).isEmpty {
                    workHeader("This week", count: 0)
                    Text("Nothing due this week")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                        .padding(.vertical, 8)
                }
                if showsNextWeek {
                    workHeader("Next week", count: bucket(.nextWeek).count)
                    workRows(bucket(.nextWeek), byID: byID)
                }
                ForEach(months, id: \.month) { month in
                    foldRow(title: monthTitle(month.month),
                            subtitle: rangeLabel(month.entries),
                            isOpen: openMonths.contains(month.month)) {
                        toggleMonth(month.month)
                    }
                    if openMonths.contains(month.month) { workRows(month.entries, byID: byID) }
                }
                if !bucket(.noDate).isEmpty {
                    let undated = bucket(.noDate)
                    foldRow(title: "No date",
                            subtitle: "\(undated.count) item\(undated.count == 1 ? "" : "s")",
                            isOpen: showUndated) {
                        withAnimation(MobileTheme.spring) { showUndated.toggle() }
                    }
                    if showUndated { workRows(undated, byID: byID) }
                }
            }
        }
    }

    /// "THIS WEEK · 4" — the class page's own caps label, with the count where the eye
    /// already looks for it.
    private func workHeader(_ title: String, count: Int, late: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).edCapsLabel()
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(late ? AtlasTheme.Colors.danger : MobileTheme.faint)
        }
        .foregroundStyle(late ? AtlasTheme.Colors.danger : MobileTheme.muted)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func workRows(_ entries: [TermTimeline.Entry], byID: [UUID: TaskItem]) -> some View {
        ForEach(entries) { entry in
            if let task = byID[entry.id] {
                workRow(task)
                    // The store's linger removes the row inside a spring, and this is
                    // what turns that into a slide-out rather than a blink.
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private func workRow(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            CheckCircle(done: task.done, color: task.spaceColor) { toggle(task) }
            Text(task.title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(task.done ? MobileTheme.faint : MobileTheme.ink)
                .strikethrough(task.done, color: MobileTheme.faint)
            Spacer(minLength: 8)
            let due = TaskItem.dueLabel(for: task.dueDate, allDay: task.allDay)
            if !due.isEmpty {
                Text(due)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(task.isOverdue(now: Date())
                                     ? AtlasTheme.Colors.danger : MobileTheme.muted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { detail = .task(task) }
        .padding(.vertical, 10)
        .edHairlineBelow()
    }

    /// "Rest of September · 2 items · SEP 8 — Show". Months start CLOSED: the whole
    /// semester stays one tap away as a handful of rows.
    private func foldRow(title: String, subtitle: String,
                         isOpen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
                Spacer(minLength: 6)
                Text(isOpen ? "Hide" : "Show")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.accentText)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .edHairlineBelow()
    }

    private func toggleMonth(_ month: Date) {
        MobileTheme.Haptic.tap()
        withAnimation(MobileTheme.spring) {
            if openMonths.contains(month) { openMonths.remove(month) } else { openMonths.insert(month) }
        }
    }

    /// "Rest of September" for the month in progress, "October" after it, and a year once
    /// the term crosses into one — the Mac's wording.
    private func monthTitle(_ month: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(month, equalTo: now, toGranularity: .month) {
            return "Rest of \(ClassHubView.monthFormat.string(from: month))"
        }
        if cal.isDate(month, equalTo: now, toGranularity: .year) {
            return ClassHubView.monthFormat.string(from: month)
        }
        return ClassHubView.monthYearFormat.string(from: month)
    }

    /// "12 items · SEP 8 – SEP 30".
    private func rangeLabel(_ entries: [TermTimeline.Entry]) -> String {
        let count = "\(entries.count) item\(entries.count == 1 ? "" : "s")"
        guard let first = entries.first?.date, let last = entries.last?.date else { return count }
        let from = ClassHubView.dayFormat.string(from: first).uppercased()
        let to = ClassHubView.dayFormat.string(from: last).uppercased()
        return from == to ? "\(count) · \(from)" : "\(count) · \(from) – \(to)"
    }

    private static let monthFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f
    }()
    private static let monthYearFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        updated.completedAt = updated.done ? Date() : nil
        Task { await store.setTaskDone(updated) }
    }

    // MARK: - Notes

    private func notesBlock(_ project: Project) -> some View {
        let notes = store.snapshot.notes
            .filter { $0.projectID == project.id }
            .sorted { $0.updatedAt > $1.updatedAt }
        return section("Notes", action: nil) {
            if notes.isEmpty {
                Text("No notes for this class yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
            } else {
                ForEach(notes) { note in
                    HStack(spacing: 8) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .lineLimit(1)
                        if note.isExternal {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MobileTheme.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingNote = note }
                    .padding(.vertical, 12)
                    .edHairlineBelow()
                }
            }
        }
    }

    // MARK: - Section chrome

    /// A caps-labelled band with an optional trailing action — the class page's one shape.
    private func section<C: View>(_ title: String,
                                  action: (String, () -> Void)?,
                                  @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).edCapsLabel()
                Spacer()
                if let action {
                    Button(action: action.1) {
                        Text(action.0)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(.bottom, 30)
    }
}

// `ClassInfoFormat` moved to AtlasCore so the Mac class page and the iOS class hub
// parse grade weights identically (a "200% total" bug came from them drifting apart).

