import SwiftUI
import AtlasCore

/// The quiet mono footer under a task/event list that expands a hidden
/// completed/past group in place — "3 COMPLETED ˅". Shared by the project
/// and space detail views.
struct RevealRow: View {
    let count: Int
    let noun: String
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("\(count) \(noun)")
                    .atlasMono(size: 10, weight: .medium)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Project/space event row — color bar, title, mono time line. `dimmed` is the
/// past-event treatment: faded bar, muted title, and a dated time line (a past
/// event with a bare time would be ambiguous). Shared so the two views can't
/// drift apart.
struct LifecycleEventRow: View {
    let event: CalendarEvent
    var dimmed = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3, height: 30)
                .opacity(dimmed ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(dimmed ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                Text(dimmed
                     ? "\(LifecycleDate.short(event.start)) · \(event.timeLabel)"
                     : "\(event.timeLabel) · \(event.durationLabel)")
                    .atlasMono(size: 11)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

/// "JUL 3" — the short mono date completed/past rows carry.
enum LifecycleDate {
    static func short(_ date: Date) -> String {
        formatter.string(from: date).uppercased()
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
