import SwiftUI
import AtlasCore

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
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AtlasTheme.wash(color))
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
            .strokeBorder(color.opacity(0.5), lineWidth: AtlasTheme.rule))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .frame(width: 170, alignment: .leading)
    }
}

// MARK: - Hour gutter (shared left rail of time labels)

struct HourGutter: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                Text(label(for: hour))
                    .atlasMono(size: 10, weight: .bold)
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
    /// Shared 60-sec clock, forwarded to each EventTile so past tiles dim live.
    let now: Date
    let isToday: Bool
    /// Called when the user taps an empty area of the grid (not on an EventTile).
    /// `hour` is a fractional clock hour (e.g. 9.5 = 9:30 AM).
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    /// Called when the user left-clicks an event tile. Feeds into `CalendarView.openSource(for:)`.
    var onTapEvent: ((CalendarEvent) -> Void)? = nil
    /// Live drag position while the user is dragging an already-placed event (global coords).
    var onDragEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    /// Drag released — CalendarView resolves the global point to a new slot.
    var onDropEvent: ((CalendarEvent, CGPoint) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            // Exclude all-day events from timed packing — they corrupt lane widths
            // and render off-screen at negative Y. Week mode shows them in AllDayRowView;
            // day mode omits them from the grid (acceptable for v1).
            let positioned = packEventsIntoLanes(events.filter { !$0.isAllDay })
            // Collapse near-simultaneous timed deadlines so their dashed-line labels don't
            // overprint (computed off-body to keep the grid's type-check budget light).
            let deadlineClusters = clusterTimedDeadlines(
                events.filter { $0.isDeadline && $0.hasSpecificTime },
                gapPoints: CalendarLayout.deadlineLabelHeight
            )
            // Reserve a narrow left rail for timed-deadline flags — but only on days that have
            // any, so other days keep the full tile width. Tiles inset by railWidth, so a
            // deadline marker is NEVER drawn over a tile.
            let railWidth: CGFloat = deadlineClusters.isEmpty ? 0 : CalendarLayout.deadlineRailWidth
            ZStack(alignment: .topLeading) {
                // Subtle today-column background tint — first layer so everything renders on top
                if isToday {
                    AtlasTheme.Colors.accent.opacity(0.04)
                }
                hourLines
                if isToday { nowLine }
                // Event/work-block tiles sit to the RIGHT of the deadline rail (inset by
                // railWidth) so flags and tiles never collide.
                ForEach(positioned) { item in
                    tile(for: item, columnWidth: geo.size.width - railWidth, xInset: railWidth)
                }
                // Timed-deadline flags live in the dedicated left rail (off the tiles), drawn
                // last so they stay clickable and on top. A lone deadline is one red flag; a
                // cluster of near-simultaneous ones collapses to a flag + count badge (tap →
                // popover listing each). All-day deadlines stay in the top DUE strip.
                ForEach(deadlineClusters) { cluster in
                    let off = CalendarLayout.offsetHours(for: cluster.representative.start) * CalendarLayout.hourHeight
                    if off >= 0, off <= CalendarLayout.totalHeight {
                        DeadlineRailMarker(cluster: cluster)
                            .offset(y: off - CalendarLayout.deadlineLabelHeight / 2)
                    }
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
                        .frame(height: 2)
                    Circle()
                        .fill(AtlasTheme.Colors.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: -3)
                }
                .offset(y: offset)
            }
        }
    }

    private func tile(for item: PositionedEvent, columnWidth: CGFloat, xInset: CGFloat) -> some View {
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
        return EventTile(event: ev, now: now, compact: height < 44)
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
            .offset(x: x + xInset, y: y)
            // Drag-to-reschedule: mirrors the tray's custom DragGesture approach.
            // simultaneousGesture lets the tap still fire on a stationary click.
            // Read-only events (Apple/Google) are excluded via the guard.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        guard !ev.isReadOnly else { return }
                        onDragEvent?(ev, value.location)
                    }
                    .onEnded { value in
                        guard !ev.isReadOnly else { return }
                        onDropEvent?(ev, value.location)
                    }
            )
    }
}

// MARK: - Event tile

struct EventTile: View {
    let event: CalendarEvent
    /// The shared 60-sec clock (AppState.now) — drives the "passed" dim live as time elapses.
    let now: Date
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tileAccentColor)
                .frame(width: 3)
            HStack(alignment: .top, spacing: 4) {
                // Work-block checkbox — signals "planned work, tickable" (vs a fixed event).
                if event.isWorkBlock {
                    Image(systemName: "square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tileAccentColor)
                        .padding(.top, compact ? 0 : 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    if !compact {
                        Text("\(event.timeLabel) · \(event.durationLabel)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Fixed events sit borderless on their tinted fill (mobile block idiom); a
        // work-block keeps a dashed outline to read as provisional, tickable work.
        .overlay {
            if event.isWorkBlock {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tileAccentColor.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        // A timed tile whose slot has fully elapsed reads as "passed" — dimmed only, no
        // strike-through or recolor. Covers work-blocks (scheduled-but-unfinished; done ones
        // never reach the grid) and events incl. read-only external ones (simply ended < now).
        .opacity(event.end < now ? 0.65 : 1)
    }

    private var tileAccentColor: Color {
        event.isReadOnly ? AtlasTheme.Colors.textSecondary : event.color
    }

    /// Work-blocks read as provisional (fainter fill, dashed border); fixed events are solid.
    private var backgroundOpacity: Double {
        if event.isWorkBlock { return 0.10 }
        return event.isReadOnly ? 0.08 : 0.14
    }

    private var titleColor: Color {
        event.isReadOnly ? AtlasTheme.Colors.textSecondary : AtlasTheme.Colors.textPrimary
    }
}

// MARK: - Timed deadline rail marker (grid)

/// A timed-deadline marker that lives in the dedicated left rail (never over a tile): a red
/// `flag.fill` at the due-time y. A lone deadline is a single flag; near-simultaneous ones
/// collapse to a flag + count badge ("3"). Tapping opens a popover listing each deadline
/// (title + time). The red flag iconography is deliberately distinct from a rounded event tile,
/// so a deadline never reads as a calendar event.
struct DeadlineRailMarker: View {
    let cluster: DeadlineCluster
    @State private var showList = false

    var body: some View {
        Button { showList.toggle() } label: {
            Image(systemName: "flag.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AtlasTheme.Colors.danger)
                .frame(width: CalendarLayout.deadlineRailWidth,
                       height: CalendarLayout.deadlineLabelHeight)
                // Count badge (kept inside the rail) when several deadlines collapse into one.
                .overlay(alignment: .topTrailing) {
                    if cluster.count > 1 {
                        Text("\(cluster.count)")
                            .font(.system(size: 7, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 10, height: 10)
                            .background(Circle().fill(AtlasTheme.Colors.danger))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showList, arrowEdge: .leading) {
            DeadlineListPopover(deadlines: cluster.events)
        }
    }
}

/// Compact list shown when a deadline cluster / overflow chip is expanded: one "flag · title …
/// time" row per deadline. Shared by the grid marker, the day DUE strip, and the week cells.
struct DeadlineListPopover: View {
    let deadlines: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(deadlines) { dl in
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(dl.color)
                    Text(dl.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    if dl.hasSpecificTime {
                        Spacer(minLength: 12)
                        Text(dl.timeLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180, alignment: .leading)
    }
}

// MARK: - Deadline strip

/// A horizontal rail of deadline flag-pills, pinned above the time grid so due-dates are
/// always visible (they never scroll away with the grid). Orange normally, red when overdue
/// (the pill carries its colour via `event.color`). Deadlines are Atlas-only — never on Google.
struct DeadlineStrip: View {
    let deadlines: [CalendarEvent]
    @State private var showOverflow = false

    /// Inline pill budget before collapsing the rest into a "+N" overflow chip, so a busy day
    /// doesn't push the strip off-screen. A simple cap (not width-measured) — keeps it light.
    private let maxVisible = 4

    var body: some View {
        let visible = Array(deadlines.prefix(maxVisible))
        let overflow = Array(deadlines.dropFirst(maxVisible))
        HStack(spacing: 6) {
            Text("DUE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            ForEach(visible) { dl in
                pill(dl)
            }
            if !overflow.isEmpty {
                Button { showOverflow.toggle() } label: {
                    atlasTag(text: "+\(overflow.count)", color: AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOverflow, arrowEdge: .bottom) {
                    DeadlineListPopover(deadlines: overflow)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ dl: CalendarEvent) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill").font(.system(size: 8))
            Text(dl.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if dl.hasSpecificTime {
                Text(dl.timeLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(dl.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(AtlasTheme.wash(dl.color), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Day view (gutter + one column)

struct DayCalendarView: View {
    let date: Date
    let events: [CalendarEvent]
    /// Shared 60-sec clock (AppState.now), forwarded down so past tiles dim live.
    let now: Date
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    var onTapEvent: ((CalendarEvent) -> Void)? = nil
    var onDragEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    var onDropEvent: ((CalendarEvent, CGPoint) -> Void)? = nil

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
                                now: now,
                                isToday: Calendar.current.isDateInToday(date),
                                onTapEmpty: onTapEmpty,
                                onTapEvent: onTapEvent,
                                onDragEvent: onDragEvent,
                                onDropEvent: onDropEvent
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
        // Use a VStack spacer so the anchor has the correct LAYOUT position — .offset() is
        // visual-only and scrollTo uses the layout frame, which would always land at y=0.
        let offsetY = CalendarLayout.offsetHours(for: Date()) * CalendarLayout.hourHeight + 6
        return VStack(spacing: 0) {
            Color.clear.frame(width: 1, height: offsetY)
            Color.clear.frame(width: 1, height: 1).id("nowAnchor")
        }
    }
}

// MARK: - Week view (gutter + 7 columns with sticky header)

struct WeekGridView: View {
    let days: [Date]
    /// Provides the (space-filtered) events for a given day.
    let eventsProvider: (Date) -> [CalendarEvent]
    /// Shared 60-sec clock (AppState.now), forwarded down so past tiles dim live.
    let now: Date
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    var onTapEvent: ((CalendarEvent) -> Void)? = nil
    var onDragEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    var onDropEvent: ((CalendarEvent, CGPoint) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            // columnWidth accounts for all fixed chrome around the day columns: the hour
            // gutter + its 6 pt trailing padding, the VStack's 8 pt trailing padding, and
            // the (days.count - 1) 1 pt column dividers.
            let columnWidth = (geo.size.width - CalendarLayout.gutterWidth - 6 - 8
                               - CGFloat(days.count - 1)) / CGFloat(days.count)
            VStack(spacing: 0) {
                // ── Sticky weekday / date header ──────────────────────────────
                WeekColumnHeader(days: days, columnWidth: columnWidth)

                Divider().overlay(AtlasTheme.Colors.border)

                // ── All-day event strip (collapses to 0 height when empty) ────
                AllDayRowView(
                    days: days,
                    columnWidth: columnWidth,
                    now: now,
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
                                        now: now,
                                        isToday: Calendar.current.isDateInToday(day),
                                        onTapEmpty: onTapEmpty,
                                        onTapEvent: onTapEvent,
                                        onDragEvent: onDragEvent,
                                        onDropEvent: onDropEvent
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

                            // Sentinel at the current-time Y — VStack spacer keeps the layout
                            // position correct; .offset() is visual-only and scrollTo lands at y=0.
                            let offsetY = CalendarLayout.offsetHours(for: Date()) * CalendarLayout.hourHeight + 6
                            VStack(spacing: 0) {
                                Color.clear.frame(width: 1, height: offsetY)
                                Color.clear.frame(width: 1, height: 1).id("nowAnchor")
                            }
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
