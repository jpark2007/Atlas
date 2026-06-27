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
                // Subtle today-column background tint — first layer so everything renders on top
                if isToday {
                    AtlasTheme.Colors.accent.opacity(0.04)
                }
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
        ScrollViewReader { proxy in
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
                .id("dayGrid")
                .padding(.trailing, 8)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .onAppear {
                autoScrollToNow(proxy: proxy, anchor: "dayGrid")
            }
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
            // columnWidth accounts for the gutter and the 8 pt trailing padding on the VStack.
            // The 1 pt column dividers are additive (same as in the original layout).
            let columnWidth = (geo.size.width - CalendarLayout.gutterWidth - 8) / CGFloat(days.count)
            VStack(spacing: 0) {
                // ── Sticky weekday / date header ──────────────────────────────
                WeekColumnHeader(days: days, columnWidth: columnWidth)

                Divider().overlay(AtlasTheme.Colors.border)

                // ── All-day event strip (collapses to 0 height when empty) ────
                AllDayRowView(
                    days: days,
                    columnWidth: columnWidth,
                    eventsProvider: eventsProvider
                )

                // ── Scrollable time grid (auto-scrolls to current hour) ───────
                ScrollViewReader { proxy in
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
                        .id("weekGrid")
                        .padding(.top, 6)
                        .padding(.bottom, 16)
                    }
                    .onAppear {
                        autoScrollToNow(proxy: proxy, anchor: "weekGrid")
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }
}

// MARK: - Auto-scroll helper

/// Scrolls `proxy` so that the current hour is visible near the top of the
/// scroll container, with ~1 h of context above it.
/// Only fires when the current time falls within [startHour, endHour].
private func autoScrollToNow(proxy: ScrollViewProxy, anchor: String) {
    let currentOffset = CalendarLayout.offsetHours(for: Date())
    let totalHours = CGFloat(CalendarLayout.endHour - CalendarLayout.startHour)
    guard currentOffset >= 0, currentOffset <= totalHours else { return }

    // Show ~1 hour of context above the current time
    let targetY     = max(0, currentOffset - 1) * CalendarLayout.hourHeight
    let fraction    = targetY / CalendarLayout.totalHeight

    // Defer one run-loop so the ScrollView has finished its initial layout
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        proxy.scrollTo(anchor, anchor: UnitPoint(x: 0, y: fraction))
    }
}
