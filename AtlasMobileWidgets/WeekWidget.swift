import WidgetKit
import SwiftUI

// MARK: - Timeline

struct WeekEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .empty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let now = Date()
        let entry = WeekEntry(date: now, snapshot: SharedSnapshot.read() ?? .empty)
        // Nothing inside a week row changes by the minute — only which row is TODAY,
        // which flips at midnight.
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        completion(Timeline(entries: [entry], policy: .after(midnight ?? now.addingTimeInterval(3600))))
    }
}

// MARK: - Widget

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AtlasWeek", provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                .containerBackground(WidgetTheme.bg, for: .widget)
        }
        .configurationDisplayName("This week")
        .description("What meets each day, and how much is due.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - View

struct WeekWidgetView: View {
    let entry: WeekEntry

    private var days: [SharedSnapshot.WeekDay] { entry.snapshot.week }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                Spacer()
                Text("\(days.reduce(0) { $0 + $1.dueCount }) due")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(WidgetTheme.faint)
            }
            .padding(.bottom, 8)

            if days.isEmpty {
                emptyState
            } else {
                ForEach(days, id: \.startEpoch) { day in
                    dayRow(day)
                    if day.startEpoch != days.last?.startEpoch {
                        Rectangle().fill(WidgetTheme.hairline).frame(height: 1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "atlas://today")!)
    }

    private func dayRow(_ day: SharedSnapshot.WeekDay) -> some View {
        let isToday = Calendar.current.isDate(Date(timeIntervalSince1970: day.startEpoch),
                                              inSameDayAs: entry.date)
        return HStack(alignment: .center, spacing: 8) {
            Text(day.label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(isToday ? WidgetTheme.accentText : WidgetTheme.muted)
                .frame(width: 34, alignment: .leading)

            if day.meets.isEmpty {
                Text("—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.faint)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(day.meets.prefix(3).enumerated()), id: \.offset) { _, chip in
                        HStack(spacing: 3.5) {
                            Circle().fill(Color(hex: chip.colorHex)).frame(width: 6, height: 6)
                            Text(chip.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(WidgetTheme.ink)
                                .lineLimit(1)
                        }
                    }
                    if day.meets.count > 3 {
                        Text("+\(day.meets.count - 3)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(WidgetTheme.faint)
                    }
                }
            }

            Spacer(minLength: 4)

            if day.dueCount > 0 {
                Text("\(day.dueCount) due")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(WidgetTheme.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(WidgetTheme.ink, lineWidth: 1.2))
            }
        }
        .padding(.vertical, 7)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("No classes yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
            Text("add a class in school")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.faint)
            Spacer(minLength: 0)
        }
    }
}
