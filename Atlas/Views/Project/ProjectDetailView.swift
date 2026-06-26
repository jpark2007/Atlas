import SwiftUI

struct ProjectDetailView: View {
    let project: Project

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                // Main column
                VStack(alignment: .leading, spacing: 22) {
                    badges
                    titleBlock
                    if !project.overview.isEmpty { overview }
                    if !project.assignments.isEmpty { assignments }
                    if !project.pinned.isEmpty { pinned }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Linked references column
                if !project.backlinks.isEmpty {
                    linkedReferences.frame(width: 280)
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }

    private var badges: some View {
        HStack(spacing: 8) {
            tag(text: project.spaceName, color: project.spaceColor, filled: true)
            if project.isClass { tag(text: "Class", color: AtlasTheme.Colors.textSecondary, filled: false) }
            if project.canvasSynced {
                tag(text: "CANVAS SYNCED", color: AtlasTheme.Colors.accent, filled: false)
            }
        }
    }

    private func tag(text: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 5) {
            if filled { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(text == text.uppercased() ? 0.8 : 0)
        }
        .foregroundStyle(filled ? color : color.opacity(0.9))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background((filled ? color : color).opacity(0.12))
        .clipShape(Capsule())
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let code = project.code {
                    Text(code)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                }
                Text(project.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            HStack(spacing: 16) {
                if let m = project.meetingInfo { metaItem("calendar", m) }
                if let i = project.instructor { metaItem("person", i) }
                if project.canvasSynced { metaItem("folder", "Canvas + Drive", accent: true) }
            }
        }
    }

    private func metaItem(_ icon: String, _ text: String, accent: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(accent ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textSecondary)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("OVERVIEW")
            Text(project.overview)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
    }

    private var assignments: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ASSIGNMENTS & TASKS")
            VStack(spacing: 0) {
                ForEach(Array(project.assignments.enumerated()), id: \.element.id) { i, task in
                    HStack(spacing: 12) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
                        Text(task.title)
                            .font(.system(size: 13))
                            .strikethrough(task.done)
                            .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                        Spacer()
                        Text(task.dueLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                        statusPill(task.status)
                    }
                    .padding(.vertical, 9)
                    if i < project.assignments.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.border)
                    }
                }
            }
        }
    }

    private func statusPill(_ status: TaskStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .open:      return ("Open", AtlasTheme.Colors.textMuted)
            case .dueSoon:   return ("Due soon", AtlasTheme.Colors.accent)
            case .upcoming:  return ("Upcoming", AtlasTheme.Colors.textSecondary)
            case .submitted: return ("Submitted", AtlasTheme.Colors.green)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 66, alignment: .trailing)
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PINNED RESOURCES")
            HStack(spacing: 10) {
                ForEach(project.pinned) { res in
                    HStack(spacing: 8) {
                        Image(systemName: res.systemImage)
                            .font(.system(size: 12))
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(res.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Text(res.source)
                                .font(.system(size: 10))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(AtlasTheme.Colors.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AtlasTheme.Colors.border, lineWidth: 1))
                }
            }
        }
    }

    private var linkedReferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11))
                Text("LINKED REFERENCES").font(AtlasTheme.Font.sectionLabel()).tracking(0.8)
                Text("\(project.backlinks.count)")
                    .font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .foregroundStyle(AtlasTheme.Colors.textSecondary)

            ForEach(project.backlinks) { link in
                HStack(spacing: 10) {
                    Circle().fill(link.color).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text(link.meta)
                            .font(.system(size: 10))
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(AtlasTheme.Colors.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AtlasTheme.Colors.border, lineWidth: 1))
            }

            Text("Every task, event, and note that mentions this Class appears here automatically.")
                .font(.system(size: 10))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.top, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AtlasTheme.Font.sectionLabel())
            .tracking(0.8)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }
}
