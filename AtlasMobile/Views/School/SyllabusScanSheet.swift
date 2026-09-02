import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import AtlasCore

/// Colors the review sheet needs that the mobile palette doesn't carry: the amber a
/// server-flagged meeting row wears, and the blue of an "already in Canvas" badge. Both
/// are the app's own tokens (`Theme.swift` late / school), spelled here rather than
/// widening `MobileTheme` for one screen.
private let scanLate = Color(hex: "c2710b")
private let scanDupInk = Color(hex: "3f6ea8")
private let scanDupTint = Color(hex: "5b9bd5")
private let scanBorderStrong = Color(hex: "211d17").opacity(0.28)

/// Scan a syllabus from the phone: pick pages (or paste the text) → read them → review
/// what was found in three steps → commit.
///
/// This is the door the spec calls out as *more* natural on a phone — the syllabus is
/// usually already a screenshot in the camera roll. Three pickers land in the same place:
/// Photos (`PhotosPicker`), Files (`fileImporter`, which is where a PDF lives), and the
/// paste box for a syllabus that only exists as a Canvas page.
///
/// The review step is the point. Phase 1 allows exactly one review screen in Atlas and
/// this is it: nothing the model produced touches a class, a task list or the calendar
/// until the button at the bottom of the LAST step is pressed. Shape follows the Mac twin
/// and the picked mockups (3C wizard, 3A work cards, 7A intake).
struct SyllabusScanSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    /// The class the scan was launched from — every detected group starts pointed here.
    let project: Project

    private enum Phase { case pick, scanning, review }
    private enum Step: Int, CaseIterable { case meetings, grading, work }
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
    /// What the server flagged about this scan — a meeting block it refused to trust.
    @State private var warnings: [String] = []
    @State private var expandedMonths: Set<String> = []
    @State private var expandedPolicies: Set<UUID> = []
    /// Which section the student says they're in, per group. Absent ⇒ keep them all.
    @State private var sectionPick: [UUID: String] = [:]
    /// Sections pre-picked from the class's existing meeting schedule, so the option that
    /// was chosen for the student can say so.
    @State private var autoMatched: [UUID: String] = [:]
    /// The one inline message line — never a dialog on top of this sheet.
    @State private var message: String?

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false

    /// One page queued for the scan: the encoded image plus what to call it in the list.
    private struct ScannedPage: Identifiable {
        let id = UUID()
        let label: String
        let image: SyllabusScanImage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch phase {
                case .pick:     pickStep
                case .scanning: scanningStep
                case .review:   reviewStep
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .photosPicker(isPresented: $showPhotosPicker,
                      selection: $photoSelection,
                      maxSelectionCount: SyllabusScan.maxImages,
                      matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .png, .jpeg, .heic, .webP],
                      allowsMultipleSelection: true) { result in
            addFiles(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(phase == .review ? "Review scan — \(project.name)" : "Scan a syllabus or schedule")
                    .edScreenTitle()
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Text(phase == .review ? "Discard" : "Cancel").edCapsLabel()
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 22)
    }

    private var headerSubtitle: String {
        guard phase == .review else {
            return "A syllabus or a course schedule — a photo, a PDF, or the text off a Canvas page. Atlas reads whichever of the meeting times, the work and the policies it states."
        }
        return "Step \(step.rawValue + 1) of 3 · nothing is added until the last step"
    }

    // MARK: - Step 1 · intake (7A)

    @ViewBuilder
    private var pickStep: some View {
        segmented(["Upload", "Paste the text"], selected: intake == .upload ? 0 : 1) { index in
            intake = index == 0 ? .upload : .paste
            message = nil
        }
        .padding(.bottom, 18)

        if intake == .upload { uploadPane } else { pastePane }

        if let note = inactiveIntakeNote {
            Text(note)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(scanLate)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }

        messageLine

        primaryButton("Read it", enabled: canScan) { runScan() }
    }

    @ViewBuilder
    private var uploadPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            pickButton("Choose from Photos", symbol: "photo.on.rectangle") { showPhotosPicker = true }
            pickButton("Choose a file or PDF", symbol: "doc.badge.plus") { showFileImporter = true }
        }

        if !pages.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(pageListHeader)
                    .edCapsLabel()
                    .padding(.bottom, 8)
                ForEach(pages) { page in
                    HStack(spacing: 10) {
                        Image(systemName: "doc").font(.system(size: 13, weight: .medium))
                        Text(page.label)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(sizeLabel(page.image.byteCount))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(MobileTheme.faint)
                        Button {
                            pages.removeAll { $0.id == page.id }
                            if pages.isEmpty { droppedPages = 0 }
                            message = nil
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(MobileTheme.faint)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(MobileTheme.muted)
                    .padding(.vertical, 10)
                    .edHairlineBelow()
                }
            }
            .padding(.top, 24)
        }

        Text("No PDF? Some syllabi live as a Canvas page — switch to **Paste the text** and paste the whole page.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)
    }

    @ViewBuilder
    private var pastePane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $pastedText)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .tint(MobileTheme.accent)
                .padding(8)
                .frame(minHeight: 260)
            if pastedText.isEmpty {
                Text("Paste the Canvas syllabus page here — meetings, grading, policies and dates.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .padding(.horizontal, 13).padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
            .fill(Color.white.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
            .strokeBorder(scanBorderStrong, lineWidth: 1.5))

        Text(pastedText.isEmpty
             ? "Select the whole page in Canvas, copy, and paste. Atlas reads the same things it reads off a PDF."
             : "\(pastedText.count) characters")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .padding(.top, 12)
    }

    private func pickButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 15.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(MobileTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scanningStep: some View {
        VStack(spacing: 12) {
            AtlasLoader(size: 26)
            Text(intake == .paste
                 ? "Reading what you pasted…"
                 : "Reading \(pages.count) \(pages.count == 1 ? "page" : "pages")…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Step 2 · review (3C wizard, 3A work cards)

    @ViewBuilder
    private var reviewStep: some View {
        if !groups.isEmpty {
            segmented(["Meetings", "Grading", "Work · \(totalItems)"], selected: step.rawValue) { index in
                step = Step(rawValue: index) ?? .meetings
            }
            .padding(.bottom, 18)
        }
        if truncated {
            Text("Some pages were cut off — scan the rest separately if something's missing.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(scanLate)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
        }
        if groups.isEmpty {
            Text("Nothing readable came back. A sharper photo of the schedule page — or the text pasted straight off the Canvas page — usually does it.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
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
            .padding(.bottom, 20)
        }
        messageLine
        reviewFooter
    }

    @ViewBuilder
    private var reviewFooter: some View {
        switch step {
        case .meetings:
            primaryButton("Meetings look right — next", enabled: true) { step = .grading }
        case .grading:
            primaryButton("Grading looks right — next", enabled: true) { step = .work }
        case .work:
            VStack(spacing: 10) {
                primaryButton(commitLabel, enabled: canCommit) { Task { await commit() } }
                if skippedDuplicates > 0 {
                    Text("Skipping \(skippedDuplicates) duplicate\(skippedDuplicates == 1 ? "" : "s") — check one to add it anyway")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private func groupHeader(_ group: Binding<SyllabusDraftGroup>) -> some View {
        HStack(spacing: 10) {
            Text(group.wrappedValue.detectedLabel.isEmpty ? "Unnamed class"
                                                          : group.wrappedValue.detectedLabel)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
            Spacer(minLength: 8)
            Menu {
                ForEach(targetChoices) { klass in
                    Button(klass.name) {
                        group.wrappedValue.targetClassID = klass.id
                        // A different class has different existing work — re-decide the badges,
                        // and re-ask the keep/replace question against what IT has saved.
                        let marked = SyllabusDedupe.markingExisting(
                            [group.wrappedValue], tasks: store.snapshot.tasks,
                            events: store.snapshot.events)[0]
                        group.wrappedValue = SyllabusRescan.keepingExisting(
                            marked, info: klass.classInfo, meetings: klass.meetingPattern)
                    }
                }
            } label: {
                Text("→ " + (targetName(group.wrappedValue.targetClassID) ?? "Pick a class"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.accentText)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Meetings step

    @ViewBuilder
    private func meetingsCard(_ group: Binding<SyllabusDraftGroup>) -> some View {
        let blocks = group.wrappedValue.meetingPattern
        card(title: "Meetings found",
             count: blocks.isEmpty ? "none" : "\(blocks.count) row\(blocks.count == 1 ? "" : "s") · editable",
             toggle: blocks.isEmpty ? nil : group.includeMeetingPattern) {
            if blocks.isEmpty {
                Text("The syllabus didn't state a weekly meeting pattern. You can add one on the class page.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let saved = SyllabusRescan.meetingSummary(existingMeetings(group.wrappedValue)) {
                    replaceChoice("Replaces your current schedule (\(saved))",
                                  replace: group.includeMeetingPattern)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(blocks.indices, id: \.self) { index in
                        meetingRow(group, index)
                            .padding(.vertical, 12)
                            .edHairlineBelow()
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

    private func meetingRow(_ group: Binding<SyllabusDraftGroup>, _ index: Int) -> some View {
        let block = group.wrappedValue.meetingPattern[index]
        let on = group.wrappedValue.meetingIncluded.indices.contains(index)
            ? group.wrappedValue.meetingIncluded[index] : true
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
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
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(fieldChrome)
                }
                if let label = block.sectionLabel, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MobileTheme.faint)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(MobileTheme.hairline, lineWidth: 1))
                }
                Spacer(minLength: 0)
            }
            dayPills(group.meetingPattern[index].weekdays)
            HStack(spacing: 6) {
                timeField(group.meetingPattern[index].start)
                Text("–").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MobileTheme.faint)
                timeField(group.meetingPattern[index].end)
                TextField("Room", text: Binding(get: { block.location ?? "" },
                                                set: { group.wrappedValue.meetingPattern[index].location =
                                                        $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tint(MobileTheme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldChrome)
            }
        }
        .opacity(on ? 1 : 0.55)
    }

    private func timeField(_ text: Binding<String>) -> some View {
        TextField("HH:mm", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .tint(MobileTheme.accent)
            .frame(width: 54)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(fieldChrome)
    }

    /// Su…Sa, Foundation's own numbering — tapping one adds or removes that day.
    private func dayPills(_ weekdays: Binding<[Int]>) -> some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.wrappedValue.contains(day)
                Button {
                    MobileTheme.Haptic.selection()
                    if on { weekdays.wrappedValue.removeAll { $0 == day } }
                    else { weekdays.wrappedValue = (weekdays.wrappedValue + [day]).sorted() }
                } label: {
                    Text(String(MeetingPatternFormat.weekdayInitials[day].prefix(1)))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(on ? MobileTheme.bg : MobileTheme.faint)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? MobileTheme.ink : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(on ? Color.clear : MobileTheme.hairline, lineWidth: 1))
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
        return VStack(alignment: .leading, spacing: 10) {
            Text(auto == nil
                 ? "This syllabus lists \(choices.count) sections. Which one are you in?"
                 : "This syllabus lists \(choices.count) sections. Atlas picked the one on your schedule — change it if that's not yours.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(choices, id: \.self) { choice in
                sectionOption(choice, subtitle: sectionSubtitle(group.wrappedValue, choice),
                              matched: auto == choice, on: picked == choice) {
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
        .padding(.horizontal, 13).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .fill(MobileTheme.accent.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .strokeBorder(MobileTheme.accent.opacity(0.35), lineWidth: 1))
        .padding(.top, 12)
    }

    private func sectionOption(_ title: String, subtitle: String?, matched: Bool, on: Bool,
                               action: @escaping () -> Void) -> some View {
        Button {
            MobileTheme.Haptic.selection()
            action()
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .strokeBorder(on ? MobileTheme.ink : scanBorderStrong, lineWidth: on ? 4.5 : 1.5)
                    .frame(width: 15, height: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitle.map { "\(title) · \($0)" } ?? title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(on ? MobileTheme.ink : MobileTheme.muted)
                        .lineLimit(1)
                    if matched {
                        Text("Matches your schedule")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(on ? MobileTheme.ink : scanBorderStrong, lineWidth: 1.5))
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
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(scanLate)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .fill(scanLate.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(scanLate.opacity(0.55), lineWidth: 1))
    }

    // MARK: - Grading step

    @ViewBuilder
    private func gradingCard(_ group: Binding<SyllabusDraftGroup>) -> some View {
        if let info = group.wrappedValue.classInfo {
            card(title: "Grading & policies",
                 count: "\(info.gradeWeights.count) · \(info.policies.count)",
                 toggle: group.includeClassInfo) {
                if let saved = SyllabusRescan.classInfoSummary(existingInfo(group.wrappedValue)) {
                    replaceChoice("Replaces what's saved now (\(saved))",
                                  replace: group.includeClassInfo)
                }
                VStack(alignment: .leading, spacing: 14) {
                    if !info.gradeWeights.isEmpty {
                        VStack(spacing: 7) {
                            ForEach(info.gradeWeights, id: \.self) { line in
                                weightChip(line)
                            }
                        }
                    }
                    if !info.policies.isEmpty { policyList(group.wrappedValue) }
                    if let hours = info.officeHours, !hours.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Office hours").edCapsLabel()
                            Text(hours)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(MobileTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .opacity(group.wrappedValue.includeClassInfo ? 1 : 0.45)
            }
        } else {
            card(title: "Grading & policies", count: "none") {
                Text("The syllabus didn't state grade weights or policies Atlas could read.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weightChip(_ line: String) -> some View {
        let parts = SyllabusReview.weightChip(line)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(parts.label)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
            Spacer(minLength: 8)
            if let percent = parts.percent {
                Text(percent)
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .strokeBorder(scanBorderStrong, lineWidth: 1))
    }

    private func policyList(_ group: SyllabusDraftGroup) -> some View {
        let policies = group.classInfo?.policies ?? []
        let open = expandedPolicies.contains(group.id)
        let shown = open ? policies : Array(policies.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, policy in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(MobileTheme.faint)
                        .padding(.top, 2)
                    Text(policy)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .edHairlineBelow()
            }
            if policies.count > 2 {
                Button {
                    if open { expandedPolicies.remove(group.id) }
                    else { expandedPolicies.insert(group.id) }
                } label: {
                    revealLabel(open ? "Show fewer policies" : "Show \(policies.count - 2) more policies")
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Work step (3A — grouped by month)

    @ViewBuilder
    private func workCards(_ group: Binding<SyllabusDraftGroup>) -> some View {
        let buckets = SyllabusReview.monthBuckets(group.wrappedValue.items)
        if buckets.isEmpty {
            card(title: "Work", count: "none") {
                Text("No assignments or exams came out of this scan.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
        ForEach(buckets) { bucket in
            monthCard(group, bucket.title, bucket.indices)
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
                        .padding(.vertical, 12)
                        .edHairlineBelow()
                }
                if indices.count > monthPreview {
                    Button {
                        if open { expandedMonths.remove(key) } else { expandedMonths.insert(key) }
                    } label: {
                        revealLabel(open ? "Show fewer"
                                         : "Show \(indices.count - monthPreview) more in \(title)")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
            }
        }
    }

    /// How many rows a month card shows before "show N more".
    private let monthPreview = 5

    private func itemRow(_ item: Binding<SyllabusDraftItem>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox(item.include).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: item.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.wrappedValue.include ? MobileTheme.ink : MobileTheme.faint)
                    .tint(MobileTheme.accent)
                HStack(spacing: 8) {
                    Button {
                        MobileTheme.Haptic.selection()
                        item.wrappedValue.kind = item.wrappedValue.kind == .task ? .event : .task
                    } label: {
                        Text(item.wrappedValue.kind.label.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MobileTheme.faint)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(MobileTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    // §C4: what the class already has, un-checked and named. Never dropped —
                    // the student sees everything the scan found and can accept it anyway.
                    if item.wrappedValue.alreadyExists { duplicateChip }
                    // A schedule's week row ("Sept 28–Oct 2") gives a range, not a day: the
                    // date is the end of it, and the student should know before it commits.
                    if item.wrappedValue.dateApproximate { approximateChip }
                    Spacer(minLength: 0)
                }
                if item.wrappedValue.date == nil {
                    Button { item.wrappedValue.date = defaultItemDate() } label: {
                        Text("No date — tap to set one")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(scanLate)
                    }
                    .buttonStyle(.plain)
                } else {
                    DatePicker("", selection: Binding(get: { item.wrappedValue.date ?? Date() },
                                                      set: { item.wrappedValue.date = $0 }),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
        }
        .opacity(item.wrappedValue.include ? 1 : 0.7)
    }

    private var duplicateChip: some View {
        Text("Already in Canvas")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(scanDupInk)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .fill(scanDupTint.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(scanDupTint.opacity(0.55), lineWidth: 1))
    }

    /// A date the scan inferred from a week or a date range rather than read off the page.
    private var approximateChip: some View {
        Text("Approximate")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1))
    }

    // MARK: - Re-scanning a class that already has this section

    /// What the target class has saved right now — the thing a commit would replace.
    private func existingInfo(_ group: SyllabusDraftGroup) -> ClassInfoCard? {
        group.targetClassID.flatMap { pid in store.snapshot.projects.first { $0.id == pid }?.classInfo }
    }

    private func existingMeetings(_ group: SyllabusDraftGroup) -> [MeetingBlock] {
        group.targetClassID.flatMap { pid in
            store.snapshot.projects.first { $0.id == pid }?.meetingPattern
        } ?? []
    }

    /// The keep/replace line — shown only when this class already HAS the section the scan
    /// found. It starts on "Keep existing", so a second scan can never quietly take away a
    /// card the student fixed by hand.
    private func replaceChoice(_ text: String, replace: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(text)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                choicePill("Keep existing", on: !replace.wrappedValue) { replace.wrappedValue = false }
                choicePill("Replace", on: replace.wrappedValue) { replace.wrappedValue = true }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .strokeBorder(MobileTheme.hairline, lineWidth: 1))
    }

    private func choicePill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            MobileTheme.Haptic.selection()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(on ? MobileTheme.bg : MobileTheme.muted)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                    .fill(on ? MobileTheme.ink : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                    .strokeBorder(on ? Color.clear : scanBorderStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared chrome

    private func card<Content: View>(title: String,
                                     count: String?,
                                     toggle: Binding<Bool>? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let toggle { checkbox(toggle) }
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Spacer(minLength: 8)
                if let count {
                    Text(count)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusCard, style: .continuous)
            .strokeBorder(MobileTheme.hairline, lineWidth: 1))
    }

    private var fieldChrome: some View {
        RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .fill(Color.white.opacity(0.4))
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(scanBorderStrong, lineWidth: 1.5))
    }

    private func revealLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(MobileTheme.muted)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(scanBorderStrong, lineWidth: 1.5))
    }

    private func segmented(_ titles: [String], selected: Int,
                           onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    MobileTheme.Haptic.selection()
                    onPick(index)
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(index == selected ? MobileTheme.bg : MobileTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(index == selected ? MobileTheme.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < titles.count - 1 {
                    Rectangle().fill(MobileTheme.hairline).frame(width: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
            .strokeBorder(scanBorderStrong, lineWidth: 1.5))
    }

    private func checkbox(_ on: Binding<Bool>) -> some View {
        Button {
            MobileTheme.Haptic.selection()
            on.wrappedValue.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(on.wrappedValue ? MobileTheme.ink : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(on.wrappedValue ? MobileTheme.ink : scanBorderStrong, lineWidth: 1.5))
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(MobileTheme.bg)
                    .opacity(on.wrappedValue ? 1 : 0))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(enabled ? MobileTheme.ink : MobileTheme.faint)
                .frame(maxWidth: .infinity)
                .edOutlineControl()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.top, 24)
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private var messageLine: some View {
        if let message {
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(scanLate)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    // MARK: - Choices

    /// The classes a group can be filed under: the class's own term when it has one,
    /// else every live class (a class awaiting the term prompt still needs a target).
    private var targetChoices: [Project] {
        let term = project.termID.flatMap { id in store.terms.first { $0.id == id } } ?? store.activeTerm
        if let term {
            let inTerm = store.classes(in: term)
            if !inTerm.isEmpty { return inTerm }
        }
        return store.snapshot.projects.filter { $0.isClass && $0.archivedAt == nil }
    }

    private func targetName(_ id: UUID?) -> String? {
        id.flatMap { pid in store.snapshot.projects.first { $0.id == pid }?.name }
    }

    /// The page-list heading. A truncated file must never read as complete.
    private var pageListHeader: String {
        let base = "\(pages.count) \(pages.count == 1 ? "page" : "pages")"
        return droppedPages > 0 ? base + " · \(droppedPages) not read" : base
    }

    /// Content sitting in the tab that ISN'T being sent. A scan sends one lane, so say
    /// which one before the button is pressed rather than dropping the other in silence.
    private var inactiveIntakeNote: String? {
        if intake == .upload,
           !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The text you pasted isn't part of this scan — Atlas reads the pages. Switch back to Paste the text to read that instead."
        }
        if intake == .paste, !pages.isEmpty {
            return "The \(pages.count) page\(pages.count == 1 ? "" : "s") you added aren't part of this scan — Atlas reads what's pasted here. Switch back to Upload to read them instead."
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

    /// A blank date starts at today, 11:59 PM — the hour a syllabus usually means by "due".
    private func defaultItemDate() -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date()
    }

    private func sizeLabel(_ bytes: Int) -> String {
        bytes < 1_000_000 ? "\(bytes / 1000) KB"
                          : String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    // MARK: - Picking pages

    /// Camera-roll pages. `PhotosPickerItem` hands back raw bytes; the UTType it reports
    /// is the media type the endpoint needs, defaulting to PNG when it says nothing.
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        message = nil
        var index = 1
        for item in items {
            guard pages.count < SyllabusScan.maxImages else {
                message = "Atlas reads at most \(SyllabusScan.maxImages) pages at a time — the rest weren't added."
                break
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                message = "Couldn't read one of those photos."
                continue
            }
            let type = item.supportedContentTypes.first
            let media = type?.preferredMIMEType ?? "image/png"
            pages.append(ScannedPage(label: "Photo \(index)",
                                     image: SyllabusScanImage(bytes: data, mediaType: media)))
            sources.append(SyllabusPages.Source(name: "Photo \(index).\(type?.preferredFilenameExtension ?? "png")",
                                                data: data,
                                                isPDF: false))
            index += 1
        }
        photoSelection = []
        if let error = validationMessage() { message = error }
    }

    /// Files-app pages. A PDF is rasterized here — the endpoint is images only.
    private func addFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            message = "Couldn't open that file."
            return
        }
        message = nil
        for url in urls {
            let room = SyllabusScan.maxImages - pages.count
            guard room > 0 else {
                message = "Atlas reads at most \(SyllabusScan.maxImages) pages at a time — the rest weren't added."
                break
            }
            // Files handed over by the importer live outside the sandbox until asked for.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
        guard store.session != nil else {
            message = "Sign in to Atlas to scan a syllabus."
            return
        }
        message = nil
        phase = .scanning
        step = .meetings
        let images = pages.map(\.image)
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let paste = intake == .paste
        let term = store.activeTerm

        Task { @MainActor in
            do {
                let scanner = SyllabusScan(session: { store.session })
                let response = paste
                    ? try await scanner.scan(text: text, termStart: term?.startsOn, termEnd: term?.endsOn)
                    : try await scanner.scan(images: images, termStart: term?.startsOn, termEnd: term?.endsOn)
                var drafted = SyllabusDedupe.markingExisting(
                    SyllabusDraft.groups(from: response, defaultTarget: project.id),
                    tasks: store.snapshot.tasks, events: store.snapshot.events)
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
        // scan row that doesn't exist yet server-side (FK-constrained, 0046). Mirrors
        // the Mac. A commit that files nothing gets no receipt.
        let scan = groups.contains(where: { $0.targetClassID != nil })
            ? await store.recordScan(fileName: scanFileName,
                               kind: intake == .paste ? ScanRecord.Kind.paste
                                                      : ScanRecord.Kind.syllabus,
                               projectID: groups.compactMap(\.targetClassID).first ?? project.id)
            : nil
        for group in groups {
            guard let targetID = group.targetClassID,
                  let klass = store.snapshot.projects.first(where: { $0.id == targetID }) else { continue }

            let meetings = group.includedMeetings
            if group.includeMeetingPattern && !meetings.isEmpty {
                store.setMeetingPattern(projectID: targetID,
                                        blocks: meetings,
                                        meetingInfo: klass.meetingInfo)
            }
            if group.includeClassInfo, let info = group.classInfo {
                store.setClassInfo(projectID: targetID, info: info)
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
                    Task { await store.addEvent(event) }
                } else {
                    let due = SyllabusDraft.taskDue(for: item)
                    var task = TaskItem(title: item.title,
                                        dueLabel: TaskItem.dueLabel(for: due.dueDate,
                                                                    allDay: due.allDay),
                                        dueDate: due.dueDate)
                    task.allDay      = due.allDay
                    task.spaceName   = klass.spaceName
                    task.spaceColor  = classColor(klass)
                    task.spaceID     = klass.spaceID
                    task.projectID   = klass.id
                    task.projectName = klass.name
                    task.notes       = item.notes ?? ""
                    task.scanID      = scan?.id
                    Task { await store.addTask(task) }
                }
            }
        }
        keepTheSyllabus()
        MobileTheme.Haptic.success()
        dismiss()
    }

    /// What the source line will say this item came from: the document (or photo) the
    /// user picked, or plainly "Pasted text" when there was none. A multi-file pick is
    /// named by its first file — the merged PDF has no name of its own to report.
    private var scanFileName: String {
        if intake == .paste { return ScanRecord.pastedFileName }
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
              let session = store.session else { return }

        Task { @MainActor in
            do {
                let path = try await SyllabusStorage.upload(file.data,
                                                            contentType: file.contentType,
                                                            fileExtension: file.fileExtension,
                                                            projectID: owner,
                                                            session: session)
                store.setSyllabusPath(projectID: owner, path: path)
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
/// course packet is not a scan. UIKit twin of the Mac's `SyllabusPages`.
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
    static let renderJPEGQuality: CGFloat = 0.8

    static func read(_ url: URL, limit: Int) throws -> Reading {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            return try rasterize(url, limit: limit)
        }
        let data = try Data(contentsOf: url)
        let media = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
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
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let jpeg = page.thumbnail(of: size, for: .mediaBox)
                .jpegData(compressionQuality: renderJPEGQuality) else { return nil }
            return Page(label: "\(url.lastPathComponent) · page \(index + 1)",
                        image: SyllabusScanImage(bytes: jpeg, mediaType: "image/jpeg"))
        }
        return Reading(pages: pages, documentPages: doc.pageCount)
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
    /// handful of photos become one PDF, because a class has one syllabus, not five.
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
            } else if let image = UIImage(data: source.data), let page = PDFPage(image: image) {
                out.insert(page, at: out.pageCount)
            }
        }
        return out.pageCount > 0 ? out.dataRepresentation() : nil
    }
}
