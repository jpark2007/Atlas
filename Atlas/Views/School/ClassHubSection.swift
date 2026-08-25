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
    @State private var editingInstructor = false
    @State private var draftInstructor = ""

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
        VStack(alignment: .leading, spacing: 8) {
            Text("CLASS INFO").atlasCapsLabel()
            if !info.gradeWeights.isEmpty {
                infoGroup("How it's graded", info.gradeWeights)
            }
            if !info.policies.isEmpty {
                infoGroup("Policies", info.policies)
            }
            if let hours = info.officeHours, !hours.isEmpty {
                infoGroup("Office hours", [hours])
            }
        }
    }

    private func infoGroup(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").atlasFont(size: 13)
                    Text(line)
                        .atlasFont(size: 13, design: .rounded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
        }
    }

    private var classInfoEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLASS INFO").atlasCapsLabel()
            Text("Scan your syllabus to fill this in — grade weights, late policy, office hours.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
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
        }
    }
}

// `MeetingPatternFormat` moved to AtlasCore so the Mac class page and the iOS class hub
// describe a pattern identically (and the weekday mapping is tested once).
