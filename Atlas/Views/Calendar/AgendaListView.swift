import SwiftUI
import AtlasCore

/// The List (agenda) view: events and dated tasks in four fixed buckets —
/// **Late · Due today · Tomorrow · This week**, mirroring the iOS Schedule list.
/// Bucketing and ordering come from the pure, unit-tested `AgendaBuilder`; this view
/// only renders. Tapping a row hands the item back to the parent (event → open source,
/// task → Day view).
struct AgendaListView: View {
    let buckets: [AgendaBucket]
    let onSelect: (AgendaItem) -> Void

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        Group {
            if buckets.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(buckets) { bucket in
                            bucketView(bucket)
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
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bucket

    private func bucketView(_ bucket: AgendaBucket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(bucket.kind.title.uppercased())
                    .atlasMono(size: 12, weight: .bold)
                    .tracking(1.2)
                    // Late wears the amber state colour; every other bucket is plain ink —
                    // "this week" is not a warning.
                    .foregroundStyle(bucket.kind == .late
                                     ? AtlasTheme.Colors.late
                                     : AtlasTheme.Colors.textPrimary)
                Spacer()
                Text("\(bucket.items.count)")
                    .atlasMono(size: 11, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Divider().overlay(bucket.kind == .late
                              ? AtlasTheme.Colors.late.opacity(0.4)
                              : AtlasTheme.Colors.border)

            VStack(spacing: 0) {
                ForEach(bucket.items) { item in
                    row(item, late: bucket.kind == .late)
                }
            }
        }
    }

    private func row(_ item: AgendaItem, late: Bool) -> some View {
        HStack(spacing: 12) {
            Text(timeLabel(item, late: late))
                .atlasMono(size: 11, weight: .medium)
                .foregroundStyle(late ? AtlasTheme.Colors.late : AtlasTheme.Colors.textSecondary)
                .frame(width: 70, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(item.color)
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if item.kind == .task {
                        Image(systemName: "checkmark.square")
                            .atlasFont(size: 11, weight: .medium)
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

    /// A late row states the date it was due ("Mar 3") rather than a meaningless "All day" —
    /// the original date is the point.
    private func timeLabel(_ item: AgendaItem, late: Bool) -> String {
        if late { return Self.lateDateFormat.string(from: item.date) }
        return item.allDay ? "All day" : Self.timeFormat.string(from: item.date)
    }

    private static let lateDateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func durationLabel(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
