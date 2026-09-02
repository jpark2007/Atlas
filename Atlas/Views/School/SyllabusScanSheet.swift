import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AtlasCore

/// Scan a syllabus: choose pages (or paste the text) → read them → review what was
/// found in three steps → commit.
///
/// The review step is the point. Phase 1 allows exactly one review screen in Atlas and
/// this is it: nothing the model produced touches a class, a task list or the calendar
/// until the button at the bottom of the LAST step is pressed.
///
/// Shape follows the picked mockups in `docs/specs/redesign-2026-08/ui-density-syllabus-ideas.html`:
/// **3C** for the wizard (Meetings → Grading → Work), **3A** for the work step's
/// month-grouped cards, **7A** for the two-tab intake.
struct SyllabusScanSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    /// The class the scan was launched from — every detected group starts pointed here.
    let project: Project

    private enum Phase { case pick, scanning, review }

    /// 3C: one decision at a time. Add is only reachable from the last step.
    private enum Step: Int, CaseIterable { case meetings, grading, work }

    /// 7A: the two doors into the same scan.
    private enum Intake { case upload, paste }

    @State private var phase: Phase = .pick
    @State private var step: Step = .meetings
    @State private var intake: Intake = .upload
    @State private var pages: [ScannedPage] = []
    /// Pages of the picked PDFs past the cap that Atlas is NOT reading. Kept so the page
    /// list can't present a 26-page file as if all of it went in.
    @State private var droppedPages = 0
    /// The syllabus pasted in as text, for the classes whose syllabus is a Canvas page
    /// with nothing to download (handoff §E).
    @State private var pastedText = ""
    /// The files the user actually picked, kept verbatim. The pages above are rasterized
    /// for the model; THIS is what gets stored so the syllabus can be read again later.
    @State private var sources: [SyllabusPages.Source] = []
    @State private var groups: [SyllabusDraftGroup] = []
    @State private var truncated = false
    /// What the server flagged about this scan — a meeting block it refused to trust, a
    /// cap that bit. Shown in the amber treatment on the meetings step.
    @State private var warnings: [String] = []
    /// Which month cards have been expanded past their first few rows, keyed
    /// "<group id>|<month>". Collapsed is the default: 43 items is a scroll, not a review.
    @State private var expandedMonths: Set<String> = []
    /// Groups whose policy list has been opened past the first two.
    @State private var expandedPolicies: Set<UUID> = []
    /// Which section the student says they're in, per group. Absent ⇒ keep them all.
    @State private var sectionPick: [UUID: String] = [:]
    /// Sections pre-picked from the class's existing meeting schedule, so the option that
    /// was chosen for the student can say so.
    @State private var autoMatched: [UUID: String] = [:]
    /// The one inline message line — never a dialog on top of this dialog.
    @State private var message: String?

    /// One page queued for the scan: the encoded image plus what to call it in the list.
    private struct ScannedPage: Identifiable {
        let id = UUID()
        let label: String
        let image: SyllabusScanImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            Group {
                switch phase {
                case .pick:     pickStep
                case .scanning: scanningStep
                case .review:   reviewStep
                }
            }
        }
        .frame(width: 760, height: 700, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(phase == .review ? "Review scan — \(project.name)" : "Scan a syllabus or schedule")
                    .atlasFont(size: 20, weight: .bold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(headerSubtitle)
                    .atlasFont(size: 12.5, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(phase == .review ? "Discard" : "Cancel") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    private var headerSubtitle: String {
        guard phase == .review else {
            return "A syllabus or a course schedule — a PDF, a screenshot, or the text off a Canvas page. Atlas reads whichever of the meeting times, the work and the policies it states."
        }
        return "Step \(step.rawValue + 1) of 3 · nothing is added until the last step"
    }

    // MARK: - Step 1 · intake (7A)

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    segmented(["Upload a PDF", "Paste the text"],
                              selected: intake == .upload ? 0 : 1) { index in
                        intake = index == 0 ? .upload : .paste
                        message = nil
                    }

                    if intake == .upload { uploadPane } else { pastePane }

                    if let note = inactiveIntakeNote {
                        Text(note)
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.late)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    messageLine
                }
                .padding(24)
            }
            Spacer(minLength: 0)
            footer {
                filledButton("Read it", enabled: canScan) { runScan() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var uploadPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: choosePages) {
                VStack(spacing: 5) {
                    Text(pages.isEmpty ? "Drop the syllabus or schedule PDF here" : "Add more pages…")
                        .atlasFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("or choose a file · up to \(SyllabusScan.maxImages) pages")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.borderStrong,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadDropped(providers)
                return true
            }

            if !pages.isEmpty { pageList }

            Text("No PDF? Some syllabi live as a Canvas page — switch to **Paste the text** and paste the whole page.")
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pageListHeader).atlasCapsLabel()
            ForEach(pages) { page in
                HStack(spacing: 8) {
                    Image(systemName: "doc").atlasFont(size: 11)
                    Text(page.label)
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .lineLimit(1)
                    Spacer()
                    Text(sizeLabel(page.image.byteCount))
                        .atlasMono(size: 11)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Button {
                        pages.removeAll { $0.id == page.id }
                        if pages.isEmpty { droppedPages = 0 }
                        message = nil
                    } label: {
                        Image(systemName: "minus.circle")
                            .atlasFont(size: 12)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
        }
    }

    private var pastePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .scrollContentBackground(.hidden)
                    .atlasFont(size: 12.5, weight: .regular, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .padding(8)
                    .frame(minHeight: 260)
                if pastedText.isEmpty {
                    Text("Paste the Canvas syllabus page here — meetings, grading, policies and dates.")
                        .atlasFont(size: 12.5, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5))

            Text(pastedText.isEmpty
                 ? "Select the whole page in Canvas, copy, and paste. Atlas reads the same things it reads off a PDF."
                 : "\(pastedText.count) characters")
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    private var scanningStep: some View {
        VStack(spacing: 12) {
            Spacer()
            AtlasLoader(size: 26)
            Text(intake == .paste
                 ? "Reading what you pasted…"
                 : "Reading \(pages.count) \(pages.count == 1 ? "page" : "pages")…")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 2 · review (3C wizard, 3A work cards)

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !groups.isEmpty {
                segmented(["1 · Meetings", "2 · Grading", "3 · Work (\(totalItems))"],
                          selected: step.rawValue) { index in
                    step = Step(rawValue: index) ?? .meetings
                }
                .padding(.horizontal, 24).padding(.top, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if truncated {
                        Text("Some pages were cut off — scan the rest separately if something's missing.")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.late)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if groups.isEmpty {
                        Text("Nothing readable came back. A sharper screenshot of the schedule page — or the text pasted straight off the Canvas page — usually does it.")
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach($groups) { $group in
                        VStack(alignment: .leading, spacing: 14) {
                            groupHeader($group)
                            switch step {
                            case .meetings: meetingsCard($group)
                            case .grading:  gradingCard($group)
                            case .work:     workCards($group)
                            }
                        }
                    }
                    messageLine
                }
                .padding(24)
            }
            footer {
                switch step {
                case .meetings:
                    filledButton("Meetings look right — next", enabled: true) { step = .grading }
                case .grading:
                    filledButton("Grading looks right — next", enabled: true) { step = .work }
                case .work:
                    if skippedDuplicates > 0 {
                        quietLabel("Skip \(skippedDuplicates) duplicate\(skippedDuplicates == 1 ? "" : "s")")
                    }
                    filledButton(commitLabel, enabled: canCommit) { Task { await commit() } }
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private func groupHeader(_ group: Binding<SyllabusDraftGroup>) -> some View {
        HStack(spacing: 8) {
            Text(group.wrappedValue.detectedLabel.isEmpty ? "Unnamed class"
                                                          : group.wrappedValue.detectedLabel)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Menu {
                ForEach(targetChoices, id: \.id) { klass in
                    Button(klass.name) {
                        group.wrappedValue.targetClassID = klass.id
                        // A different class has different existing work — re-decide the badges,
                        // and re-ask the keep/replace question against what IT has saved.
                        let marked = SyllabusDedupe.markingExisting(
                            [group.wrappedValue], tasks: state.tasks, events: state.events)[0]
                        group.wrappedValue = SyllabusRescan.keepingExisting(
                            marked, info: klass.classInfo, meetings: klass.meetingPattern)
                    }
                }
            } label: {
                Text("→ " + (targetName(group.wrappedValue.targetClassID) ?? "Pick a class"))
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Meetings step

    private func meetingsCard(_ group: Binding<SyllabusDraftGroup>) -> some View {
        let blocks = group.wrappedValue.meetingPattern
        return VStack(alignment: .leading, spacing: 12) {
            card(title: "Meetings found",
                 count: blocks.isEmpty ? "none" : "\(blocks.count) row\(blocks.count == 1 ? "" : "s") · editable",
                 toggle: blocks.isEmpty ? nil : group.includeMeetingPattern) {
                if blocks.isEmpty {
                    Text("The syllabus didn't state a weekly meeting pattern. You can add one on the class page.")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if let saved = SyllabusRescan.meetingSummary(existingMeetings(group.wrappedValue)) {
                        replaceChoice("Replaces your current schedule (\(saved))",
                                      replace: group.includeMeetingPattern)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(blocks.indices, id: \.self) { index in
                            meetingRow(group, index)
                                .padding(.vertical, 9)
                                .atlasHairlineBelow()
                        }
                    }
                    .opacity(group.wrappedValue.includeMeetingPattern ? 1 : 0.45)
                    if group.wrappedValue.sectionChoices.count > 1 {
                        sectionPicker(group)
                    }
                }
            }
            ForEach(warnings, id: \.self) { warning in
                suspiciousRow(warning)
            }
        }
    }

    private func meetingRow(_ group: Binding<SyllabusDraftGroup>, _ index: Int) -> some View {
        let block = group.wrappedValue.meetingPattern[index]
        let on = group.wrappedValue.meetingIncluded.indices.contains(index)
            ? group.wrappedValue.meetingIncluded[index] : true
        return HStack(spacing: 8) {
            checkbox(Binding(get: { on },
                             set: { new in
                                 if group.wrappedValue.meetingIncluded.indices.contains(index) {
                                     group.wrappedValue.meetingIncluded[index] = new
                                 }
                             }))
            Menu {
                ForEach(MeetingPatternFormat.kinds, id: \.self) { kind in
                    Button(MeetingPatternFormat.kindLabel(kind)) {
                        group.wrappedValue.meetingPattern[index].kind = kind
                    }
                }
            } label: {
                Text(MeetingPatternFormat.kindLabel(block.kind))
                    .atlasFont(size: 12.5, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(fieldChrome)

            dayPills(group.meetingPattern[index].weekdays)

            HStack(spacing: 4) {
                timeField(group.meetingPattern[index].start)
                Text("–").atlasFont(size: 12, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                timeField(group.meetingPattern[index].end)
            }

            TextField("Room", text: Binding(get: { block.location ?? "" },
                                            set: { group.wrappedValue.meetingPattern[index].location =
                                                    $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.plain)
                .atlasFont(size: 12.5, weight: .semibold, design: .rounded)
                .frame(width: 110)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(fieldChrome)

            if let label = block.sectionLabel, !label.isEmpty {
                Text(label)
                    .atlasMono(size: 9.5, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .opacity(on ? 1 : 0.55)
    }

    private func timeField(_ text: Binding<String>) -> some View {
        TextField("HH:mm", text: text)
            .textFieldStyle(.plain)
            .atlasFont(size: 12.5, weight: .semibold, design: .rounded)
            .frame(width: 52)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(fieldChrome)
    }

    /// Su…Sa, Foundation's own numbering — tapping one adds or removes that day.
    private func dayPills(_ weekdays: Binding<[Int]>) -> some View {
        HStack(spacing: 3) {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.wrappedValue.contains(day)
                Button {
                    if on { weekdays.wrappedValue.removeAll { $0 == day } }
                    else { weekdays.wrappedValue = (weekdays.wrappedValue + [day]).sorted() }
                } label: {
                    Text(String(MeetingPatternFormat.weekdayInitials[day].prefix(1)))
                        .atlasFont(size: 10.5, weight: .bold, design: .rounded)
                        .foregroundStyle(on ? AtlasTheme.Colors.bgBase : AtlasTheme.Colors.textMuted)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? AtlasTheme.Colors.textPrimary : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(on ? Color.clear : AtlasTheme.Colors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// §C1: the syllabus lists every section; only the student knows which one is theirs.
    private func sectionPicker(_ group: Binding<SyllabusDraftGroup>) -> some View {
        let choices = group.wrappedValue.sectionChoices
        let picked = sectionPick[group.wrappedValue.id]
        let auto = autoMatched[group.wrappedValue.id]
        return VStack(alignment: .leading, spacing: 9) {
            Text(auto == nil
                 ? "This syllabus lists \(choices.count) sections. Which one are you in?"
                 : "This syllabus lists \(choices.count) sections. Atlas picked the one on your schedule — change it if that's not yours.")
                .atlasFont(size: 13, weight: .bold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 7)],
                      alignment: .leading, spacing: 7) {
                ForEach(choices, id: \.self) { choice in
                    sectionOption(choice, subtitle: sectionSubtitle(group.wrappedValue, choice),
                                  matched: auto == choice,
                                  on: picked == choice) {
                        sectionPick[group.wrappedValue.id] = choice
                        group.wrappedValue.chooseSection(choice)
                    }
                }
                sectionOption("Import all \(choices.count)", subtitle: nil,
                              matched: false, on: picked == nil) {
                    sectionPick[group.wrappedValue.id] = nil
                    group.wrappedValue.chooseSection(nil)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AtlasTheme.Colors.accent.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.accent.opacity(0.35), lineWidth: 1))
        .padding(.top, 10)
    }

    private func sectionOption(_ title: String, subtitle: String?, matched: Bool, on: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .strokeBorder(on ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.borderStrong,
                                  lineWidth: on ? 3.5 : 1.5)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitle.map { "\(title) · \($0)" } ?? title)
                        .atlasFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(on ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                        .lineLimit(1)
                    if matched {
                        Text("Matches your schedule")
                            .atlasFont(size: 10.5, weight: .semibold, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.borderStrong,
                              lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func sectionSubtitle(_ group: SyllabusDraftGroup, _ label: String) -> String? {
        group.meetingPattern.first { $0.sectionLabel == label }
            .map { MeetingPatternFormat.describe($0) }
    }

    /// The amber "check this" treatment the mockup gives a server-flagged row.
    private func suspiciousRow(_ text: String) -> some View {
        Text(text)
            .atlasFont(size: 12, weight: .semibold, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.late)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AtlasTheme.Colors.late.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.late.opacity(0.55), lineWidth: 1))
    }

    // MARK: - Grading step

    private func gradingCard(_ group: Binding<SyllabusDraftGroup>) -> some View {
        Group {
            if let info = group.wrappedValue.classInfo {
                card(title: "Grading & policies",
                     count: "\(info.gradeWeights.count) weight\(info.gradeWeights.count == 1 ? "" : "s") · \(info.policies.count) polic\(info.policies.count == 1 ? "y" : "ies")",
                     toggle: group.includeClassInfo) {
                    if let saved = SyllabusRescan.classInfoSummary(existingInfo(group.wrappedValue)) {
                        replaceChoice("Replaces what's saved now (\(saved))",
                                      replace: group.includeClassInfo)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if !info.gradeWeights.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 7)],
                                      alignment: .leading, spacing: 7) {
                                ForEach(info.gradeWeights, id: \.self) { line in
                                    weightChip(line)
                                }
                            }
                        }
                        if !info.policies.isEmpty { policyList(group.wrappedValue) }
                        if let hours = info.officeHours, !hours.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Divider().overlay(AtlasTheme.Colors.hairline)
                                HStack(alignment: .top, spacing: 9) {
                                    Text("OFFICE HOURS").atlasCapsLabel()
                                    Text(hours)
                                        .atlasFont(size: 12.5, weight: .semibold, design: .rounded)
                                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                    .opacity(group.wrappedValue.includeClassInfo ? 1 : 0.45)
                }
            } else {
                card(title: "Grading & policies", count: "none") {
                    Text("The syllabus didn't state grade weights or policies Atlas could read.")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func weightChip(_ line: String) -> some View {
        let parts = SyllabusReview.weightChip(line)
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(parts.label)
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let percent = parts.percent {
                Text(percent)
                    .atlasFont(size: 13, weight: .heavy, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .atlasNumeric()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1))
    }

    private func policyList(_ group: SyllabusDraftGroup) -> some View {
        let policies = group.classInfo?.policies ?? []
        let open = expandedPolicies.contains(group.id)
        let shown = open ? policies : Array(policies.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, policy in
                HStack(alignment: .top, spacing: 9) {
                    Text(String(format: "%02d", index + 1))
                        .atlasMono(size: 11)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.top, 2)
                    Text(policy)
                        .atlasFont(size: 13, weight: .regular, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .atlasHairlineBelow()
            }
            if policies.count > 2 {
                Button {
                    if open { expandedPolicies.remove(group.id) }
                    else { expandedPolicies.insert(group.id) }
                } label: {
                    Text(open ? "Show fewer policies" : "Show \(policies.count - 2) more policies")
                        .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Work step (3A — grouped by month)

    private func workCards(_ group: Binding<SyllabusDraftGroup>) -> some View {
        let buckets = SyllabusReview.monthBuckets(group.wrappedValue.items)
        return VStack(alignment: .leading, spacing: 14) {
            if buckets.isEmpty {
                card(title: "Work", count: "none") {
                    Text("No assignments or exams came out of this scan.")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            ForEach(buckets) { bucket in
                monthCard(group, bucket.title, bucket.indices)
            }
        }
    }

    private func monthCard(_ group: Binding<SyllabusDraftGroup>,
                           _ title: String, _ indices: [Int]) -> some View {
        let key = "\(group.wrappedValue.id)|\(title)"
        let open = expandedMonths.contains(key)
        let shown = open ? indices : Array(indices.prefix(monthPreview))
        let selected = indices.filter { group.wrappedValue.items[$0].include }.count
        return card(title: "Work · \(title)", count: "\(selected) of \(indices.count) selected") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.self) { index in
                    itemRow(group.items[index])
                        .padding(.vertical, 10)
                        .atlasHairlineBelow()
                }
                if indices.count > monthPreview {
                    Button {
                        if open { expandedMonths.remove(key) } else { expandedMonths.insert(key) }
                    } label: {
                        Text(open ? "Show fewer" : "Show \(indices.count - monthPreview) more in \(title)")
                            .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
        }
    }

    /// How many rows a month card shows before "show N more".
    private let monthPreview = 6

    private func itemRow(_ item: Binding<SyllabusDraftItem>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox(item.include).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: item.title)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 14.5, weight: .semibold, design: .rounded)
                    .foregroundStyle(item.wrappedValue.include ? AtlasTheme.Colors.textPrimary
                                                               : AtlasTheme.Colors.textMuted)
                HStack(spacing: 8) {
                    Button {
                        item.wrappedValue.kind = item.wrappedValue.kind == .task ? .event : .task
                    } label: {
                        Text(item.wrappedValue.kind.label.uppercased())
                            .atlasMono(size: 9.5, weight: .semibold)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Switch between a deadline you owe and something that happens at a time")

                    if item.wrappedValue.date == nil {
                        Button { item.wrappedValue.date = defaultItemDate() } label: {
                            Text("No date — click to set one")
                                .atlasFont(size: 12, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.late)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // The stock picker draws a stark white system box on this cream
                        // sheet. `AtlasDateField` is the same NSDatePicker — steppers and
                        // typing intact — wearing the app's paper chrome.
                        AtlasDateField(date: Binding(get: { item.wrappedValue.date ?? Date() },
                                                     set: { item.wrappedValue.date = $0 }),
                                       includesTime: true)
                    }

                    // §C4: what the class already has, un-checked and named. Never dropped —
                    // the student sees everything the scan found and can accept it anyway.
                    if item.wrappedValue.alreadyExists {
                        duplicateChip(item.wrappedValue.existingSource ?? .existing)
                    }
                    // A schedule's week row ("Sept 28–Oct 2") gives a range, not a day: the
                    // date is the end of it, and the student should know that before it commits.
                    if item.wrappedValue.dateApproximate { approximateChip(item.wrappedValue) }
                    Spacer(minLength: 0)
                }
            }
        }
        .opacity(item.wrappedValue.include ? 1 : 0.7)
    }

    /// Names the avenue the twin actually came from — Canvas, an earlier scan, or simply
    /// the class (the semester wizard's ICS import and hand-typed items carry no
    /// provenance, so they share that last label rather than borrowing Canvas's).
    private func duplicateChip(_ source: SyllabusMatchSource) -> some View {
        Text(source.chipLabel)
            .atlasFont(size: 11.5, weight: .bold, design: .rounded)
            .foregroundStyle(Color(hex: "3f6ea8"))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AtlasTheme.Colors.school.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.school.opacity(0.55), lineWidth: 1))
            .fixedSize()
    }

    /// A date the scan inferred from a week or a date range rather than read off the page.
    /// The row's own notes carry the printed wording, so the chip repeats it as a tooltip.
    private func approximateChip(_ item: SyllabusDraftItem) -> some View {
        Text("Approximate date")
            .atlasFont(size: 11.5, weight: .bold, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
            .fixedSize()
            .help(item.notes.map { "The schedule gave a range, not a day: \($0). Atlas used its last day." }
                  ?? "The schedule gave a week or a range, not a day — Atlas used its last day.")
    }

    // MARK: - Re-scanning a class that already has this section

    /// What the target class has saved right now — the thing a commit would replace.
    private func existingInfo(_ group: SyllabusDraftGroup) -> ClassInfoCard? {
        group.targetClassID.flatMap { state.project($0)?.classInfo }
    }

    private func existingMeetings(_ group: SyllabusDraftGroup) -> [MeetingBlock] {
        group.targetClassID.flatMap { state.project($0)?.meetingPattern } ?? []
    }

    /// The keep/replace line — shown only when this class already HAS the section the scan
    /// found. It starts on "Keep existing", so a second scan can never quietly take away a
    /// card the student fixed by hand. Quiet and inline, like the row chips.
    private func replaceChoice(_ text: String, replace: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            choicePill("Keep existing", on: !replace.wrappedValue) { replace.wrappedValue = false }
            choicePill("Replace", on: replace.wrappedValue) { replace.wrappedValue = true }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
    }

    private func choicePill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 11.5, weight: .bold, design: .rounded)
                .foregroundStyle(on ? AtlasTheme.Colors.bgBase : AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(on ? AtlasTheme.Colors.textPrimary : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(on ? Color.clear : AtlasTheme.Colors.border, lineWidth: 1))
                .contentShape(Rectangle())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared chrome

    private func card<Content: View>(title: String,
                                     count: String?,
                                     toggle: Binding<Bool>? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                if let toggle { checkbox(toggle) }
                Text(title)
                    .atlasFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer(minLength: 8)
                if let count {
                    Text(count)
                        .atlasFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
    }

    private var fieldChrome: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.4))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5))
    }

    /// One row of tab labels — nothing in this strip is allowed to grow past it.
    private let segmentedHeight: CGFloat = 28

    private func segmented(_ titles: [String], selected: Int,
                           onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button { onPick(index) } label: {
                    Text(title)
                        .atlasFont(size: 11.5, weight: .bold, design: .rounded)
                        .foregroundStyle(index == selected ? AtlasTheme.Colors.bgBase
                                                           : AtlasTheme.Colors.textSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(index == selected ? AtlasTheme.Colors.textPrimary : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < titles.count - 1 {
                    Rectangle().fill(AtlasTheme.Colors.border).frame(width: 1)
                }
            }
        }
        // The dividers are Rectangles — flexible in BOTH directions. Left unpinned, the
        // strip took a share of the sheet's height beside the scroll view and drew as a
        // 350pt empty box with the tabs floating in the middle of it. One row, pinned.
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: segmentedHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5))
    }

    private func checkbox(_ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(on.wrappedValue ? AtlasTheme.Colors.textPrimary : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(on.wrappedValue ? AtlasTheme.Colors.textPrimary
                                                  : AtlasTheme.Colors.borderStrong, lineWidth: 1.5))
                .overlay(Image(systemName: "checkmark")
                    .atlasFont(size: 9, weight: .heavy)
                    .foregroundStyle(AtlasTheme.Colors.bgBase)
                    .opacity(on.wrappedValue ? 1 : 0))
                .frame(width: 15, height: 15)
        }
        .buttonStyle(.plain)
    }

    private func filledButton(_ title: String, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 12.5, weight: .bold, design: .rounded)
                .foregroundStyle(enabled ? AtlasTheme.Colors.bgBase : AtlasTheme.Colors.textMuted)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? AtlasTheme.Colors.textPrimary
                                  : AtlasTheme.Colors.textMuted.opacity(0.15)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func quietLabel(_ title: String) -> some View {
        Text(title)
            .atlasFont(size: 12, weight: .semibold, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5))
    }

    private func footer<Content: View>(@ViewBuilder trailing: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(AtlasTheme.Colors.hairline)
            HStack(spacing: 8) {
                Spacer()
                trailing()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    private var messageLine: some View {
        Group {
            if let message {
                Text(message)
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.late)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Choices

    /// The classes a group can be filed under: the class's own term when it has one,
    /// else every live class (a class awaiting the term prompt still needs a target).
    private var targetChoices: [Project] {
        let term = project.termID.flatMap { id in state.terms.first { $0.id == id } } ?? state.activeTerm
        if let term {
            let inTerm = state.classes(in: term)
            if !inTerm.isEmpty { return inTerm }
        }
        return state.allProjects.filter { $0.isClass && $0.archivedAt == nil }
    }

    private func targetName(_ id: UUID?) -> String? {
        id.flatMap { state.project($0)?.name }
    }

    /// The page-list heading. A truncated file must never read as complete.
    private var pageListHeader: String {
        let base = "\(pages.count) \(pages.count == 1 ? "PAGE" : "PAGES")"
        return droppedPages > 0 ? base + " · \(droppedPages) NOT READ" : base
    }

    /// Content sitting in the tab that ISN'T being sent. A scan sends one lane, so say
    /// which one before the button is pressed rather than dropping the other in silence.
    private var inactiveIntakeNote: String? {
        if intake == .upload,
           !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The text you pasted isn't part of this scan — Atlas reads the pages. Switch back to Paste the text to read that instead."
        }
        if intake == .paste, !pages.isEmpty {
            return "The \(pages.count) page\(pages.count == 1 ? "" : "s") you added aren't part of this scan — Atlas reads what's pasted here. Switch back to Upload a PDF to read them instead."
        }
        return nil
    }

    private var canScan: Bool {
        intake == .upload ? !pages.isEmpty
                          : pastedText.trimmingCharacters(in: .whitespacesAndNewlines).count
                                >= SyllabusScan.minTextCharacters
    }

    private var canCommit: Bool {
        groups.contains { $0.targetClassID != nil && $0.writesAnything }
    }

    private var totalItems: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    private var includedCount: Int {
        groups.filter { $0.targetClassID != nil }.reduce(0) { $0 + $1.includedItems.count }
    }

    /// Duplicates the student left unchecked — named in the footer so nothing is skipped
    /// silently (handoff §C4).
    private var skippedDuplicates: Int {
        groups.reduce(0) { $0 + $1.items.filter { $0.alreadyExists && !$0.include }.count }
    }

    private var commitLabel: String {
        includedCount == 0 ? "Add to my classes"
                           : "Add \(includedCount) \(includedCount == 1 ? "item" : "items")"
    }

    /// A blank date starts at the term's next sensible day — today, at 11:59 PM, the
    /// hour a syllabus usually means by "due".
    private func defaultItemDate() -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date()
    }

    private func sizeLabel(_ bytes: Int) -> String {
        bytes < 1_000_000 ? "\(bytes / 1000) KB"
                          : String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    // MARK: - Picking pages

    private func choosePages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .heic, .webP]
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    /// Files dropped straight onto the drop zone — the same lane the panel feeds.
    private func loadDropped(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in add([url]) }
            }
        }
    }

    private func add(_ urls: [URL]) {
        message = nil
        for url in urls {
            let room = SyllabusScan.maxImages - pages.count
            guard room > 0 else {
                message = "Atlas reads at most \(SyllabusScan.maxImages) pages at a time — the rest weren't added."
                break
            }
            do {
                let reading = try SyllabusPages.read(url, limit: room)
                pages.append(contentsOf: reading.pages
                    .map { ScannedPage(label: $0.label, image: $0.image) })
                if let source = try? SyllabusPages.source(url) { sources.append(source) }
                // Pages past the cap are gone from this scan — say it out loud.
                if reading.droppedPages > 0 {
                    droppedPages += reading.droppedPages
                    message = "\(url.lastPathComponent) is \(reading.documentPages) pages — Atlas read the first \(reading.pages.count). Scan the rest separately."
                }
            } catch {
                message = "Couldn't read \(url.lastPathComponent)."
            }
        }
        // Surface the size cap here rather than after an upload that's going to 413.
        if let error = validationMessage() { message = error }
    }

    private func validationMessage() -> String? {
        do {
            try SyllabusScan.validate(pages.map(\.image))
            return nil
        } catch AtlasAIError.noImages {
            return nil   // the button is already disabled; no need to scold
        } catch {
            return "That's more than Atlas can read at once — remove a page or two."
        }
    }

    // MARK: - Scanning

    private func runScan() {
        if intake == .upload, let error = validationMessage() { message = error; return }
        guard auth.session != nil else {
            message = "Sign in to Atlas to scan a syllabus."
            return
        }
        message = nil
        phase = .scanning
        step = .meetings
        let images = pages.map(\.image)
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let paste = intake == .paste
        let term = state.activeTerm

        Task { @MainActor in
            do {
                let scanner = SyllabusScan(session: { auth.session })
                let response = paste
                    ? try await scanner.scan(text: text, termStart: term?.startsOn, termEnd: term?.endsOn)
                    : try await scanner.scan(images: images, termStart: term?.startsOn, termEnd: term?.endsOn)
                var drafted = SyllabusDedupe.markingExisting(
                    SyllabusDraft.groups(from: response, defaultTarget: project.id),
                    tasks: state.tasks, events: state.events)
                // The class may already know which section the student attends (§6): when
                // exactly one scanned section lines up with its schedule, pick it for them.
                for index in drafted.indices {
                    guard let label = SyllabusSectionMatch.autoPick(&drafted[index],
                                                                   existing: project.meetingPattern)
                    else { continue }
                    sectionPick[drafted[index].id] = label
                    autoMatched[drafted[index].id] = label
                }
                // A re-scan of a class that already has a card or a schedule starts on
                // "Keep existing" — the sheet asks before it replaces either.
                for index in drafted.indices {
                    drafted[index] = SyllabusRescan.keepingExisting(
                        drafted[index],
                        info: existingInfo(drafted[index]),
                        meetings: existingMeetings(drafted[index]))
                }
                groups = drafted
                truncated = response.truncated
                warnings = response.warnings
                // Pasted text has no file to keep, so it becomes the stored document itself.
                if paste {
                    sources = [SyllabusPages.Source(name: "syllabus.txt",
                                                    data: Data(text.utf8),
                                                    isPDF: false)]
                }
                phase = .review
            } catch let error as AtlasAIError {
                message = plainLanguage(error)
                phase = .pick
            } catch {
                message = "Atlas couldn't reach the scanner. Check your connection and try again."
                phase = .pick
            }
        }
    }

    /// Server failures in words a student can act on — no status codes, no dialogs.
    private func plainLanguage(_ error: AtlasAIError) -> String {
        switch error {
        case .rateLimited:
            return "Too many scans just now — give it a minute and try again."
        case .tooLong:
            return intake == .paste
                ? "That's more text than Atlas can read at once — paste the schedule and grading sections."
                : "Those pages are too big to read at once — try fewer, or a smaller PDF."
        case .imagesTooLarge:
            return "Those pages are too big to read at once — try fewer, or a smaller PDF."
        case .noImages:
            return intake == .paste ? "Paste a bit more of the syllabus first."
                                    : "Add at least one page to scan."
        case .notAuthenticated:
            return "Sign in to Atlas to scan a syllabus."
        case .serverUnavailable, .parseFailed, .httpError:
            return "The scanner had trouble with that one. Try again in a moment."
        }
    }

    // MARK: - Commit (the ONLY place anything is written)

    private func commit() async {
        // One receipt per commit, AWAITED before any item write so nothing points at a
        // scan row that doesn't exist yet server-side (tasks.scan_id/events.scan_id are
        // FK-constrained to it, 0046). Every task and event below carries its id, so
        // "where did this come from?" has a real answer instead of a guess.
        // A commit that files nothing gets no receipt — provenance records what was
        // actually created, not that the sheet was opened.
        let scan = groups.contains(where: { $0.targetClassID != nil })
            ? await state.recordScan(fileName: scanFileName,
                               kind: intake == .paste ? ScanRecord.Kind.paste
                                                      : ScanRecord.Kind.syllabus,
                               projectID: groups.compactMap(\.targetClassID).first ?? project.id)
            : nil
        for group in groups {
            guard let targetID = group.targetClassID, let klass = state.project(targetID) else { continue }

            let meetings = group.includedMeetings
            if group.includeMeetingPattern && !meetings.isEmpty {
                state.setMeetingPattern(projectID: targetID,
                                        blocks: meetings,
                                        meetingInfo: klass.meetingInfo)
            }
            if group.includeClassInfo, let info = group.classInfo {
                state.setClassInfo(projectID: targetID, info: info)
            }
            for item in group.includedItems {
                // An event needs an instant to sit on. Without one it commits as an
                // undated task instead of being silently dropped.
                if item.kind == .event, let when = SyllabusDraft.eventInterval(for: item) {
                    var event = CalendarEvent(title: item.title,
                                              subtitle: klass.code ?? klass.name,
                                              start: when.start,
                                              end: when.end,
                                              color: classColor(klass),
                                              spaceName: klass.spaceName,
                                              notes: item.notes,
                                              isAllDay: when.isAllDay,
                                              projectID: klass.id,
                                              spaceID: klass.spaceID)
                    event.scanID = scan?.id
                    state.addEvent(event)
                } else {
                    let due = SyllabusDraft.taskDue(for: item)
                    let task = state.addTask(title: item.title,
                                             dueDate: due.dueDate,
                                             allDay: due.allDay,
                                             spaceName: klass.spaceName,
                                             projectName: klass.name,
                                             scanID: scan?.id)
                    if let notes = item.notes, !notes.isEmpty {
                        state.updateTaskNotes(taskId: task.id, notes: notes)
                    }
                }
            }
        }
        keepTheSyllabus()
        dismiss()
    }

    /// What the source line will say this item came from: the document the user picked,
    /// or plainly "Pasted text" when there was no document. A multi-file pick is named
    /// by its first file — the merged PDF has no name of its own to honestly report.
    private var scanFileName: String {
        if intake == .paste { return ScanRecord.pastedFileName }
        // No named file (nothing was picked through the file panel) — say "a scan"
        // rather than borrowing the paste label for something that wasn't pasted.
        return sources.first?.name ?? "Scanned document"
    }

    /// Store the document this scan was read from, so the class page can show it later.
    /// Best-effort and fire-and-forget: the scan's real product is already committed, and
    /// a storage hiccup must never cost the user their review. The pointer is written only
    /// after the upload succeeds.
    private func keepTheSyllabus() {
        let targets = groups.compactMap(\.targetClassID)
        // The syllabus belongs to the class you were standing on, unless the scan was
        // filed somewhere else entirely.
        guard let owner = targets.contains(project.id) ? project.id : targets.first,
              let file = SyllabusPages.package(sources),
              let session = auth.session else { return }

        Task { @MainActor in
            do {
                let path = try await SyllabusStorage.upload(file.data,
                                                            contentType: file.contentType,
                                                            fileExtension: file.fileExtension,
                                                            projectID: owner,
                                                            session: session)
                state.setSyllabusPath(projectID: owner, path: path)
            } catch {
                AtlasLog.append("syllabus upload failed: \(error)")
            }
        }
    }

    private func classColor(_ klass: Project) -> Color {
        klass.colorToken.map { ColorToken.color(for: $0) } ?? klass.spaceColor
    }
}


/// Turning what the user picked into pages the scan endpoint accepts. The endpoint is
/// images only, so a PDF is rasterized here — page by page, capped, because a 60-page
/// course packet is not a scan.
enum SyllabusPages {
    struct Page {
        let label: String
        let image: SyllabusScanImage
    }

    /// What one picked file yielded. `documentPages` is the file's REAL page count, so a
    /// caller can tell the user when the cap bit instead of dropping pages 21+ in silence.
    struct Reading {
        let pages: [Page]
        let documentPages: Int
        var droppedPages: Int { max(0, documentPages - pages.count) }
    }

    /// The long edge a rasterized PDF page is rendered at, and the JPEG quality it's
    /// encoded at: enough for a dense schedule table to read cleanly, small enough that
    /// twenty pages fit under the size cap.
    static let renderLongEdge: CGFloat = 1400
    static let renderJPEGQuality: Double = 0.8

    static func read(_ url: URL, limit: Int) throws -> Reading {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            return try rasterize(url, limit: limit)
        }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        let media = type.flatMap { $0.preferredMIMEType } ?? "image/png"
        return Reading(pages: [Page(label: url.lastPathComponent,
                                    image: SyllabusScanImage(bytes: data, mediaType: media))],
                       documentPages: 1)
    }

    private static func rasterize(_ url: URL, limit: Int) throws -> Reading {
        guard let doc = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        let count = min(doc.pageCount, limit)
        let pages: [Page] = (0..<count).compactMap { index in
            guard let page = doc.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = renderLongEdge / max(bounds.width, bounds.height, 1)
            let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let jpeg = jpegData(page.thumbnail(of: size, for: .mediaBox)) else { return nil }
            return Page(label: "\(url.lastPathComponent) · page \(index + 1)",
                        image: SyllabusScanImage(bytes: jpeg, mediaType: "image/jpeg"))
        }
        return Reading(pages: pages, documentPages: doc.pageCount)
    }

    private static func jpegData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: renderJPEGQuality])
    }

    // MARK: - Keeping the original

    /// One file exactly as the user picked it — never the rasterized pages. This is what
    /// gets stored, so a policy can be re-read in the professor's own document.
    struct Source {
        let name: String
        let data: Data
        let isPDF: Bool
        var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    }

    static func source(_ url: URL) throws -> Source {
        let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
        return Source(name: url.lastPathComponent, data: try Data(contentsOf: url), isPDF: isPDF)
    }

    /// The single object to store for a scan. One picked file is kept byte-for-byte; a
    /// handful of pages become one PDF, because a class has one syllabus, not five.
    static func package(_ sources: [Source]) -> (data: Data, contentType: String, fileExtension: String)? {
        guard !sources.isEmpty else { return nil }
        if sources.count == 1 {
            let only = sources[0]
            let ext = only.fileExtension.isEmpty ? (only.isPDF ? "pdf" : "png") : only.fileExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType
                ?? (only.isPDF ? "application/pdf" : "image/png")
            return (only.data, mime, ext)
        }
        guard let merged = mergedPDF(sources) else { return nil }
        return (merged, "application/pdf", "pdf")
    }

    private static func mergedPDF(_ sources: [Source]) -> Data? {
        let out = PDFDocument()
        for source in sources {
            if source.isPDF, let doc = PDFDocument(data: source.data) {
                for index in 0..<doc.pageCount {
                    guard let page = doc.page(at: index) else { continue }
                    out.insert(page, at: out.pageCount)
                }
            } else if let image = NSImage(data: source.data), let page = PDFPage(image: image) {
                out.insert(page, at: out.pageCount)
            }
        }
        return out.pageCount > 0 ? out.dataRepresentation() : nil
    }
}
