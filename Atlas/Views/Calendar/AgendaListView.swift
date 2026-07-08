import SwiftUI
import AtlasCore

/// The List (agenda) view: a chronological, day-grouped list of upcoming events
/// and scheduled/dated tasks. Ordering comes from the pure, unit-tested
/// `AgendaBuilder`; this view only renders the resulting sections. Tapping a row
/// hands the item back to the parent (event → open source, task → Day view).
struct AgendaListView: View {
    let sections: [AgendaSection]
    /// Observed "now" for Today / Tomorrow header labels.
    let now: Date
    let onSelect: (AgendaItem) -> Void

    private let calendar = Calendar.current

    private static let dayHeaderFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        Group {
            if sections.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .atlasFont(size: 33, weight: .light)
                .foregroundStyle(AtlasTheme.Colors.accent)
            Text("Nothing upcoming")
                .atlasFont(size: 17, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text("Scheduled events and dated tasks will show up here.")
                .atlasFont(size: 13, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section

    private func sectionView(_ section: AgendaSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let tag = relativeTag(for: section.day) {
                    Text(tag.uppercased())
                        .atlasMono(size: 10, weight: .bold)
                        .tracking(0.8)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                Text(Self.dayHeaderFormat.string(from: section.day))
                    .atlasMono(size: 13, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Text("\(section.items.count)")
                    .atlasMono(size: 11, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Divider().overlay(AtlasTheme.Colors.border)

            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        HStack(spacing: 12) {
            Text(timeLabel(item))
                .atlasMono(size: 11, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 70, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(item.color)
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if item.kind == .task {
                        Image(systemName: "checkmark.square")
                            .atlasFont(size: 11)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    Text(item.title)
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                }
                if !item.spaceName.isEmpty {
                    Text(item.spaceName)
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            Spacer(minLength: 0)
            if let end = item.endDate, !item.allDay {
                Text(durationLabel(from: item.date, to: end))
                    .atlasMono(size: 10, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
        // No card chrome — the row sits on the cream bg, separated by a hairline
        // rule below (editorial list idiom from the mobile timeline).
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .atlasHairlineBelow()
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item) }
    }

    // MARK: - Labels

    private func relativeTag(for day: Date) -> String? {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return nil
    }

    private func timeLabel(_ item: AgendaItem) -> String {
        item.allDay ? "All day" : Self.timeFormat.string(from: item.date)
    }

    private func durationLabel(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
