import SwiftUI

// MARK: - Drag-to-schedule plumbing (custom pointer drag)

/// A day column's hit-frame in GLOBAL coordinates, published so the tray's custom
/// drag can map a release point → (date, fractional hour) without the native
/// `.dropDestination` (which forces the green "+" copy badge and is unreliable
/// inside the scrolling grid). Global space is scroll-aware and unambiguous across
/// the grid's ScrollView — a named space measured inside the scroll skews the hour.
struct TaskDropColumn: Equatable {
    let date: Date
    let frame: CGRect
}

struct TaskDropColumnsKey: PreferenceKey {
    static var defaultValue: [TaskDropColumn] = []
    static func reduce(value: inout [TaskDropColumn], nextValue: () -> [TaskDropColumn]) {
        value.append(contentsOf: nextValue())
    }
}

/// The little chip that follows the cursor during a tray drag.
struct TaskDragPreview: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 20)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AtlasTheme.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AtlasTheme.Colors.accent.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .frame(width: 170, alignment: .leading)
    }
}

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
    /// Called when the user taps an empty area of the grid (not on an EventTile).
    /// `hour` is a fractional clock hour (e.g. 9.5 = 9:30 AM).
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    /// Called when the user left-clicks an event tile. Feeds into `CalendarView.openSource(for:)`.
    var onTapEvent: ((CalendarEvent) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            // Exclude all-day events from timed packing — they corrupt lane widths
            // and render off-screen at negative Y. Week mode shows them in AllDayRowView;
            // day mode omits them from the grid (acceptable for v1).
            let positioned = packEventsIntoLanes(events.filter { !$0.isAllDay })
            ZStack(alignment: .topLeading) {
                // Subtle today-column background tint — first layer so everything renders on top
                if isToday {
                    AtlasTheme.Colors.accent.opacity(0.04)
                }
                hourLines
                if isToday { nowLine }
                ForEach(positioned) { item in
                    tile(for: item, columnWidth: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: CalendarLayout.totalHeight, alignment: .topLeading)
            .clipped()   // keep events outside 7AM–10PM from bleeding past the column
            .contentShape(Rectangle())
            // Tap-to-create: only fires on empty grid areas because EventTile swallows
            // its own TapGesture (child gestures take priority over parent gestures).
            .onTapGesture(coordinateSpace: .local) { location in
                let hours = Double(CalendarLayout.startHour) + Double(location.y) / Double(CalendarLayout.hourHeight)
                onTapEmpty?(date, hours)
            }
            // Publish this column's hit-frame so the tray's custom drag can resolve a
            // release point → (date, hour). Replaces the native `.dropDestination`.
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: TaskDropColumnsKey.self,
                        value: [TaskDropColumn(date: date, frame: g.frame(in: .global))]
                    )
                }
            )
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
        // Build a captured closure so the compiler can close over `ev` cleanly.
        // Read-only events pass nil so openSource is a no-op (CalendarView guards it too).
        let openSourceClosure: (() -> Void)? = ev.isReadOnly
            ? nil
            : onTapEvent.map { handler in { handler(ev) } }
        return EventTile(event: ev, compact: height < 44)
            // Left-click: open source for writable events; swallow tap for read-only
            // so the parent ZStack's tap-to-create doesn't fire.
            .onTapGesture {
                // Every tile (incl. read-only) opens the detail view; the gesture still
                // consumes the tap so tap-to-create on the empty grid stays suppressed.
                onTapEvent?(ev)
            }
            // Right-click: full menu for writable; read-only label only for external events.
            .eventContextMenu(event: ev, onOpenSource: openSourceClosure)
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
                .fill(tileAccentColor)
                .frame(width: 3)
            HStack(alignment: .top, spacing: 4) {
                // Work-block checkbox — signals "planned work, tickable" (vs a fixed event).
                if event.isWorkBlock {
                    Image(systemName: "circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tileAccentColor)
                        .padding(.top, compact ? 0 : 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    if !compact {
                        Text("\(event.timeLabel) · \(event.durationLabel)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // Read-only source glyph — indicates external / Apple Calendar origin
                if event.isReadOnly {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.top, compact ? 1 : 3)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .padding(.vertical, compact ? 2 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileAccentColor.opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tileAccentColor.opacity(borderOpacity),
                        style: StrokeStyle(lineWidth: 1, dash: event.isWorkBlock ? [4, 3] : []))
        )
    }

    private var tileAccentColor: Color {
        event.isReadOnly ? AtlasTheme.Colors.textSecondary : event.color
    }

    /// Work-blocks read as provisional (fainter fill, dashed border); fixed events are solid.
    private var backgroundOpacity: Double {
        if event.isWorkBlock { return 0.10 }
        return event.isReadOnly ? 0.08 : 0.16
    }

    private var borderOpacity: Double {
        if event.isWorkBlock { return 0.55 }
        return event.isReadOnly ? 0.20 : 0.35
    }

    private var titleColor: Color {
        event.isReadOnly ? AtlasTheme.Colors.textSecondary : AtlasTheme.Colors.textPrimary
    }
}

// MARK: - Deadline strip

/// A horizontal rail of deadline flag-pills, pinned above the time grid so due-dates are
/// always visible (they never scroll away with the grid). Orange normally, red when overdue
/// (the pill carries its colour via `event.color`). Deadlines are Atlas-only — never on Google.
struct DeadlineStrip: View {
    let deadlines: [CalendarEvent]

    var body: some View {
        HStack(spacing: 6) {
            Text("DUE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            ForEach(deadlines) { dl in
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").font(.system(size: 8))
                    Text(dl.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if dl.hasSpecificTime {
                        Text(dl.timeLabel)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(dl.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(dl.color.opacity(0.12)))
                .overlay(Capsule().stroke(dl.color.opacity(0.45), lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Day view (gutter + one column)

struct DayCalendarView: View {
    let date: Date
    let events: [CalendarEvent]
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    var onTapEvent: ((CalendarEvent) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Deadline strip — pinned above the grid so due-dates never scroll out of view.
            let dayDeadlines = events.filter { $0.isDeadline }
            if !dayDeadlines.isEmpty {
                DeadlineStrip(deadlines: dayDeadlines)
                Divider().overlay(AtlasTheme.Colors.border)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 0) {
                            HourGutter()
                            DayColumnView(
                                date: date,
                                events: events,
                                isToday: Calendar.current.isDateInToday(date),
                                onTapEmpty: onTapEmpty,
                                onTapEvent: onTapEvent
                            )
                        }
                        .padding(.trailing, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 16)

                        // Zero-height sentinel anchored at the current-time Y so that
                        // scrollTo("nowAnchor", anchor: .center) lands precisely on "now".
                        nowSentinel
                    }
                }
                .onAppear {
                    scrollToNowIfVisible(proxy: proxy)
                }
            }
        }
    }

    private var nowSentinel: some View {
        let offsetY = CalendarLayout.offsetHours(for: Date()) * CalendarLayout.hourHeight + 6  // +6 for top padding
        return Color.clear
            .frame(width: 1, height: 1)
            .offset(y: offsetY)
            .id("nowAnchor")
    }
}

// MARK: - Week view (gutter + 7 columns with sticky header)

struct WeekGridView: View {
    let days: [Date]
    /// Provides the (space-filtered) events for a given day.
    let eventsProvider: (Date) -> [CalendarEvent]
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    var onTapEvent: ((CalendarEvent) -> Void)? = nil

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
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: 0) {
                                HourGutter()
                                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                    DayColumnView(
                                        date: day,
                                        events: eventsProvider(day),
                                        isToday: Calendar.current.isDateInToday(day),
                                        onTapEmpty: onTapEmpty,
                                        onTapEvent: onTapEvent
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

                            // Zero-height sentinel anchored at the current-time Y.
                            let offsetY = CalendarLayout.offsetHours(for: Date()) * CalendarLayout.hourHeight + 6
                            Color.clear
                                .frame(width: 1, height: 1)
                                .offset(y: offsetY)
                                .id("nowAnchor")
                        }
                    }
                    .onAppear {
                        scrollToNowIfVisible(proxy: proxy)
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }
}

// MARK: - Auto-scroll helper

/// Scrolls `proxy` so that the "nowAnchor" sentinel is centered in the
/// scroll container, giving a clean "now" landing position.
/// Only fires when the current time falls within [startHour, endHour].
private func scrollToNowIfVisible(proxy: ScrollViewProxy) {
    let currentOffset = CalendarLayout.offsetHours(for: Date())
    let totalHours = CGFloat(CalendarLayout.endHour - CalendarLayout.startHour)
    guard currentOffset >= 0, currentOffset <= totalHours else { return }

    // Defer one run-loop so the ScrollView has finished its initial layout
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        proxy.scrollTo("nowAnchor", anchor: .center)
    }
}
