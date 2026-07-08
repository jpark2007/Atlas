import SwiftUI
import AtlasCore

/// "The Week" — one row per project member, days across, showing anonymous
/// busy blocks as quiet tinted rectangles. Deliberately plain: no per-hour
/// grid, no drag-to-propose-meeting yet (that's a follow-up once this renders
/// correctly) — a member-by-day summary is the minimum that answers "when
/// are we all free?" at a glance.
struct TeamAvailabilityView: View {
    let project: Project
    @EnvironmentObject var state: AppState

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var members: [ProjectMemberRow] {
        state.projectMembers[project.id] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE WEEK")
                .atlasCapsLabel()

            ForEach(members, id: \.userId) { member in
                HStack(spacing: 6) {
                    Text(member.userId.uuidString.prefix(4))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 40, alignment: .leading)

                    ForEach(days, id: \.self) { day in
                        dayCell(for: member, on: day)
                    }
                }
            }

            Divider()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func dayCell(for member: ProjectMemberRow, on day: Date) -> some View {
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let busy = (state.teammateAvailability[member.userId] ?? [])
            .contains { $0.startAt < dayEnd && $0.endAt > day }

        RoundedRectangle(cornerRadius: 3)
            .fill(busy ? AtlasTheme.Colors.textMuted.opacity(0.25) : Color.clear)
            .frame(width: 28, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(AtlasTheme.Colors.textMuted.opacity(0.15), lineWidth: 0.5))
    }
}
