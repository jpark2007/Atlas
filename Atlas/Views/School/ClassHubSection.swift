import SwiftUI
import AtlasCore

/// The School-specific band of a class page: which term it belongs to, when and where it
/// meets, who teaches it, and the syllabus "Class info" card.
///
/// Assignments, notes and events below are the ordinary project sections — a class is a
/// project that knows more about itself, not a separate screen.
struct ClassHubSection: View {
    @EnvironmentObject var state: AppState
    let project: Project

    @State private var presentMeetingEditor = false
    @State private var presentSyllabusScan = false
    @State private var presentClassInfo = false
    @State private var presentClassInfoEditing = false
    @State private var presentSyllabusFile = false
    @State private var editingInstructor = false
    @State private var draftInstructor = ""
    @State private var showAllWeights = false
    @State private var infoWidth: CGFloat = 0

    /// Below this the two info cards stop fitting beside each other and stack.
    private static let sideBySideWidth: CGFloat = 460
    private static let weightPreview = 4
    private static let policyPreview = 3

    private var term: Term? {
        project.termID.flatMap { id in state.terms.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chips
            meetingBlock
            if let info = project.classInfo, !isEmpty(info) {
                classInfoCard(info)
            } else {
                classInfoEmptyState
            }
        }
        .sheet(isPresented: $presentMeetingEditor) {
            MeetingPatternSheet(project: project)
        }
        .sheet(isPresented: $presentSyllabusScan) {
            SyllabusScanSheet(project: project)
        }
        .sheet(isPresented: $presentClassInfo) {
            ClassInfoSheet(project: project, startEditing: presentClassInfoEditing)
        }
        .sheet(isPresented: $presentSyllabusFile) {
            SyllabusPreviewSheet(project: project)
        }
    }

    private func openClassInfo(editing: Bool) {
        presentClassInfoEditing = editing
        presentClassInfo = true
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 8) {
            // The term is shown when there is one and never demanded when there isn't:
            // a class that predates the term model is still just a class.
            if let term {
                atlasTag(text: term.name, color: AtlasTheme.Colors.textSecondary)
            }
            if project.archivedAt != nil {
                atlasTag(text: "Put away", color: AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
    }

    // MARK: - Meetings

    private var meetingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("MEETS").atlasCapsLabel()
                Spacer()
                Button { presentMeetingEditor = true } label: {
                    Text(project.meetingPattern.isEmpty ? "Add times" : "Edit")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
            }

            if project.meetingPattern.isEmpty {
                Text("Atlas doesn't know when this class meets, so it isn't on your calendar yet.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(project.meetingPattern.enumerated()), id: \.offset) { _, block in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").atlasFont(size: 11)
                        Text(MeetingPatternFormat.describe(block))
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                        if let location = block.location, !location.isEmpty {
                            Text("· \(location)")
                                .atlasFont(size: 13, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                        Spacer()
                    }
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
                // Where this schedule came from, said only when it changes what a scan
                // can do to it (0050): the imported one wins until the student edits it.
                if project.meetingPatternSource == .ics {
                    Text("From your imported schedule — locked")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }

            instructorRow
        }
    }

    private var instructorRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "person").atlasFont(size: 11)
            if editingInstructor {
                TextField("Instructor", text: $draftInstructor)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .frame(maxWidth: 240)
                    .onSubmit {
                        state.setInstructor(projectID: project.id, instructor: draftInstructor)
                        editingInstructor = false
                    }
            } else {
                Button {
                    draftInstructor = project.instructor ?? ""
                    editingInstructor = true
                } label: {
                    Text(project.instructor ?? "Add an instructor")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(project.instructor == nil
                                         ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Click to edit")
            }
            Spacer()
        }
        .foregroundStyle(AtlasTheme.Colors.textSecondary)
    }

    // MARK: - Class info card

    private func isEmpty(_ info: ClassInfoCard) -> Bool {
        info.gradeWeights.isEmpty && info.policies.isEmpty && (info.officeHours?.isEmpty ?? true)
    }

    /// Static syllabus facts, in the syllabus's own words. Explicitly NOT grade tracking:
    /// nothing here is computed, and Atlas never asks what you scored.
    private func classInfoCard(_ info: ClassInfoCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("CLASS INFO").atlasCapsLabel()
                Spacer()
                rescanButton
                syllabusFileButton
                Button { openClassInfo(editing: true) } label: {
                    Text("Edit")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
            }

            // Grading and policies are two different questions, so they get two cards
            // rather than one grey block. Side by side when there's room; a narrow
            // window stacks them.
            if infoWidth > 0 && infoWidth < ClassHubSection.sideBySideWidth {
                VStack(alignment: .leading, spacing: 14) {
                    if !info.gradeWeights.isEmpty { gradingColumn(info.gradeWeights) }
                    if !info.policies.isEmpty { policiesColumn(info.policies) }
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    if !info.gradeWeights.isEmpty {
                        gradingColumn(info.gradeWeights).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !info.policies.isEmpty {
                        policiesColumn(info.policies).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let hours = info.officeHours, !hours.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OFFICE HOURS").atlasCapsLabel()
                    Text(hours)
                        .atlasFont(size: 13, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ClassInfoWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ClassInfoWidthKey.self) { infoWidth = $0 }
    }

    /// Weight bullets as their own card: label left, percent right, so the shape of the
    /// grade reads down the column.
    private func gradingColumn(_ allWeights: [String]) -> some View {
        // The syllabus's own "Total: 100%" line is not a weight — the header computes
        // the total, so showing it again both misleads and double-counts.
        let weights = ClassInfoFormat.weightRows(allWeights)
        let visible = showAllWeights ? weights : Array(weights.prefix(ClassHubSection.weightPreview))
        return VStack(alignment: .leading, spacing: 0) {
            infoColumnHeader("Grading", trailing: ClassInfoFormat.weightTotal(weights))
            VStack(spacing: 6) {
                ForEach(visible, id: \.self) { line in
                    let parts = ClassInfoFormat.weight(line)
                    HStack(spacing: 8) {
                        Text(parts.label)
                            .atlasFont(size: 12, weight: .semibold, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if let percent = parts.percent {
                            Text(percent)
                                .atlasFont(size: 13, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: AtlasTheme.hairlineWidth)
                    )
                }
            }
            .padding(.top, 10)

            if weights.count > ClassHubSection.weightPreview {
                quietButton(showAllWeights ? "Show fewer" : "All \(weights.count)") {
                    showAllWeights.toggle()
                }
            }
        }
    }

    /// The first few policies, one line each. The wording you're actually held to is the
    /// full wording, and that lives in the detail sheet — hence "Read all".
    private func policiesColumn(_ policies: [String]) -> some View {
        let visible = Array(policies.prefix(ClassHubSection.policyPreview))
        return VStack(alignment: .leading, spacing: 0) {
            infoColumnHeader("Policies", trailing: "\(policies.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, line in
                    let parts = ClassInfoFormat.policy(line)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let title = parts.title {
                            Text(title)
                                .atlasFont(size: 13, weight: .bold, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        // One line here; the sheet behind "Read all" carries the wording.
                        Text(parts.body)
                            .atlasFont(size: 13, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)

                    if index < visible.count - 1 {
                        Rectangle()
                            .fill(AtlasTheme.Colors.hairline)
                            .frame(height: AtlasTheme.hairlineWidth)
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
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing)
                        .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            .padding(.bottom, 8)
            Rectangle()
                .fill(AtlasTheme.Colors.textPrimary)
                .frame(height: AtlasTheme.rule)
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .overlay(
                    Capsule().stroke(AtlasTheme.Colors.borderStrong, lineWidth: AtlasTheme.hairlineWidth)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    /// A class with a card could never be scanned again — the only door was the empty
    /// state. Second scans are ordinary (a revised syllabus, a schedule handed out later),
    /// and the review sheet now asks before it replaces anything.
    private var rescanButton: some View {
        Button { presentSyllabusScan = true } label: {
            Text("Scan a syllabus or schedule")
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
        .help("Read another syllabus or schedule into this class — you choose what it replaces")
    }

    /// Only offered once a scan has actually stored a document — a dead button on every
    /// hand-made class would be worse than none.
    @ViewBuilder
    private var syllabusFileButton: some View {
        if project.syllabusPath != nil {
            Button { presentSyllabusFile = true } label: {
                Text("View syllabus")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Open the file this class's scan was read from")
        }
    }

    private var classInfoEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLASS INFO").atlasCapsLabel()
            Text("Scan your syllabus to fill this in — grade weights, late policy, office hours.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { presentSyllabusScan = true } label: {
                    Text("Scan a syllabus")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.border,
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                // No syllabus to hand is not a reason to have no card.
                Button { openClassInfo(editing: true) } label: {
                    Text("Write it in")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// `MeetingPatternFormat` moved to AtlasCore so the Mac class page and the iOS class hub
// describe a pattern identically (and the weekday mapping is tested once).

private struct ClassInfoWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// `ClassInfoFormat` moved to AtlasCore so the Mac class page and the iOS class hub
// parse grade weights identically (a "200% total" bug came from them drifting apart).

