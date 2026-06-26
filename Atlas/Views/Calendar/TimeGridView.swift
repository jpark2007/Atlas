import SwiftUI

// MARK: - Hour gutter (shared left rail of time labels)

struct HourGutter: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                Text(label(for: hour))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: -6)
                    .frame(height: CalendarLayout.hourHeight, alignment: .top)
            }
        }
        .frame(width: CalendarLayout.gutterWidth)
        .frame(height: CalendarLayout.totalHeight, alignment: .top)
        .padding(.trailing, 6)
    }

    private func label(for hour: Int) -> String {
        let cal = Calendar.current
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return CalendarFormat.hour.string(from: date)
    }
}

// MARK: - Single day column (hour lines + events + drop target)

struct DayColumnView: View {
    let date: Date
    let events: [CalendarEvent]
    let isToday: Bool
    /// Returns true if the drop was accepted.
    let onDropTask: (UUID, Date, Double) -> Bool

    @State private var isTargeted = false

    var body: some View {
        GeometryReader { geo in
            let positioned = packEventsIntoLanes(events)
            ZStack(alignment: .topLeading) {
                hourLines
                if isTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AtlasTheme.Colors.accent.opacity(0.06))
                }
                if isToday { nowLine }
                ForEach(positioned) { item in
                    tile(for: item, columnWidth: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: CalendarLayout.totalHeight, alignment: .topLeading)
            .clipped()   // keep events outside 7AM–10PM from bleeding past the column
            .contentShape(Rectangle())
            .dropDestination(for: DraggableTaskID.self) { items, location in
                guard let first = items.first else { return false }
                let hours = Double(CalendarLayout.startHour) + Double(location.y) / Double(CalendarLayout.hourHeight)
                return onDropTask(first.id, date, hours)
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        }
        .frame(height: CalendarLayout.totalHeight)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { _ in
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(AtlasTheme.Colors.border)
                        .frame(height: 1)
                }
                .frame(height: CalendarLayout.hourHeight, alignment: .top)
            }
        }
    }

    private var nowLine: some View {
        let offset = CalendarLayout.offsetHours(for: Date()) * CalendarLayout.hourHeight
        let inRange = offset >= 0 && offset <= CalendarLayout.totalHeight
        return Group {
            if inRange {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AtlasTheme.Colors.accent)
                        .frame(height: 1.5)
                    Circle()
                        .fill(AtlasTheme.Colors.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: -3)
                }
                .offset(y: offset)
            }
        }
    }

    private func tile(for item: PositionedEvent, columnWidth: CGFloat) -> some View {
        let ev = item.event
        let y = CalendarLayout.offsetHours(for: ev.start) * CalendarLayout.hourHeight
        let rawHeight = CGFloat(ev.durationMinutes) / 60 * CalendarLayout.hourHeight
        let height = max(CalendarLayout.minEventHeight, rawHeight - 2)
        let gap: CGFloat = 3
        let laneWidth = (columnWidth - CGFloat(item.laneCount - 1) * gap) / CGFloat(item.laneCount)
        let x = CGFloat(item.lane) * (laneWidth + gap)
        return EventTile(event: ev, compact: height < 44)
            .frame(width: max(0, laneWidth - 2), height: height, alignment: .topLeading)
            .offset(x: x, y: y)
    }
}

// MARK: - Event tile

struct EventTile: View {
    let event: CalendarEvent
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                if !compact {
                    Text("\(event.timeLabel) · \(event.durationLabel)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .padding(.vertical, compact ? 2 : 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(event.color.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Day view (gutter + one column)

struct DayCalendarView: View {
    let date: Date
    let events: [CalendarEvent]
    let onDropTask: (UUID, Date, Double) -> Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                HourGutter()
                DayColumnView(
                    date: date,
                    events: events,
                    isToday: Calendar.current.isDateInToday(date),
                    onDropTask: onDropTask
                )
            }
            .padding(.trailing, 8)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Week view (gutter + 7 columns with sticky header)

struct WeekGridView: View {
    let days: [Date]
    /// Provides the (space-filtered) events for a given day.
    let eventsProvider: (Date) -> [CalendarEvent]
    let onDropTask: (UUID, Date, Double) -> Bool

    var body: some View {
        GeometryReader { geo in
            let columnWidth = (geo.size.width - CalendarLayout.gutterWidth - 8) / CGFloat(days.count)
            VStack(spacing: 0) {
                header(columnWidth: columnWidth)
                Divider().overlay(AtlasTheme.Colors.border)
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        HourGutter()
                        ForEach(Array(days.enumerated()), id: \.element) { index, day in
                            DayColumnView(
                                date: day,
                                events: eventsProvider(day),
                                isToday: Calendar.current.isDateInToday(day),
                                onDropTask: onDropTask
                            )
                            .frame(width: columnWidth)
                            if index < days.count - 1 {
                                Rectangle()
                                    .fill(AtlasTheme.Colors.border)
                                    .frame(width: 1, height: CalendarLayout.totalHeight)
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func header(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CalendarLayout.gutterWidth)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayHeader(day)
                    .frame(width: columnWidth)
                if index < days.count - 1 {
                    Color.clear.frame(width: 1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func dayHeader(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayNum = Calendar.current.component(.day, from: day)
        return VStack(spacing: 3) {
            Text(CalendarFormat.weekdayShort.string(from: day).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isToday ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            Text("\(dayNum)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isToday ? .white : AtlasTheme.Colors.textPrimary)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(isToday ? AtlasTheme.Colors.accent : .clear)
                )
        }
    }
}
