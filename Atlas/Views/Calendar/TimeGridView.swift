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
                .atlasFont(size: 13, weight: .medium, design: .rounded)
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
    /// Label every `interval` hours. Day mode labels every hour; week mode labels
    /// every third (9 AM · NOON · 3 PM · 6 PM), matching the airier week grid.
    var interval: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                Text(hour % interval == 0 ? label(for: hour) : "")
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
        if hour == 12 { return "NOON" }
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
    /// Week mode: denser tile type and hour hairlines only every 3rd hour.
    var isWeek: Bool = false
    /// Called when the user taps an empty area of the grid (not on an EventTile).
    /// `hour` is a fractional clock hour (e.g. 9.5 = 9:30 AM).
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    /// Called when the user left-clicks an event tile. Feeds into `CalendarView.openSource(for:)`.
    var onTapEvent: ((CalendarEvent) -> Void)? = nil
    /// Live drag position while the user is dragging an already-placed event (global coords).
    var onDragEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    /// Drag released — CalendarView resolves the global point to a new slot.
    var onDropEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    /// The task whose due marker is currently hovered/clicked: its work sessions glow and
    /// everything else on the grid dims. `nil` = no link active, everything renders normally.
    var linkedTaskID: UUID? = nil
    /// Set/clear the deadline↔work-session link (hover in, hover out, click to pin).
    var onLinkTask: ((UUID?) -> Void)? = nil
    /// The task checkbox reached from a work session — completes the TASK, not the session.
    var onToggleTask: ((UUID) -> Void)? = nil
    /// "+ more time" on a past session of a still-open task — plans the next session.
    var onMoreTime: ((UUID) -> Void)? = nil
    /// Planned-time readout for a due marker's task ("2.5h of 4h planned" / "1 session planned").
    var plannedLabel: ((UUID) -> String)? = nil

    var body: some View {
        GeometryReader { geo in
            // Exclude all-day events from timed packing — they corrupt lane widths
            // and render off-screen at negative Y. Deadlines are excluded outright: they are
            // NEVER blocks, they draw as rules below (a timed one is not all-day).
            let positioned = packEventsIntoLanes(events.filter { !$0.isAllDay && !$0.isDeadline })
            // Due markers: timed ones at their real due time (near-simultaneous ones collapse
            // so labels don't overprint), untimed ones parked at the end of the day.
            let markers = dueMarkerGroups(events.filter(\.isDeadline))
            ZStack(alignment: .topLeading) {
                // Subtle today-column background tint — first layer so everything renders on top
                if isToday {
                    AtlasTheme.Colors.accent.opacity(0.04)
                }
                hourLines
                if isToday { nowLine }
                // Tiles keep a 5 pt breathing inset on both column edges.
                ForEach(positioned) { item in
                    tile(for: item, columnWidth: geo.size.width - 10, xInset: 5)
                }
                // Due markers draw LAST so their rule reads across the full column width
                // and stays clickable. A deadline is a boundary, not an occupancy — it never
                // takes grid space away from the blocks it crosses.
                ForEach(markers) { group in
                    if group.y >= 0, group.y <= CalendarLayout.totalHeight {
                        DueMarkerRow(
                            group: group,
                            now: now,
                            columnWidth: geo.size.width,
                            linkedTaskID: linkedTaskID,
                            plannedLabel: plannedLabel,
                            onLinkTask: onLinkTask
                        )
                        .frame(width: geo.size.width, alignment: .leading)
                        .offset(y: group.y - CalendarLayout.deadlineLabelHeight / 2)
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
        // Week mode rules only every third hour (NOON / 3 PM / 6 PM) so the columns stay
        // open; day mode keeps a line on every hour.
        let interval = isWeek ? 3 : 1
        return VStack(spacing: 0) {
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                ZStack(alignment: .top) {
                    if hour % interval == 0 {
                        Rectangle()
                            .fill(AtlasTheme.Colors.border)
                            .frame(height: 1)
                    }
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
        return EventTile(
            event: ev,
            now: now,
            compact: height < 44,
            dense: isWeek,
            emphasis: TileEmphasis(event: ev, linkedTaskID: linkedTaskID),
            onToggleTask: onToggleTask,
            onMoreTime: onMoreTime
        )
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

/// How a tile participates in an active deadline↔work-session link.
enum TileEmphasis {
    case none      // no link is active — render normally
    case glowing   // this tile is a work session for the linked task
    case dimmed    // something else, pushed back so the linked sessions read

    init(event: CalendarEvent, linkedTaskID: UUID?) {
        guard let linked = linkedTaskID else { self = .none; return }
        // A work-block's id IS its task's id (AppState.scheduledWorkBlocks).
        self = (event.isWorkBlock && event.id == linked) ? .glowing : .dimmed
    }
}

/// One block on the grid.
///
/// **Rendering language (phase 2).** Color always says WHOSE (calendar/class), never what
/// type. Type is carried by fill and outline instead:
/// - Event / class meeting → SOLID block, no outline.
/// - Work session → a 1.5 pt full-strength dashed class-color border over a much fainter
///   wash, and NO left bar. Visibly a plan, not a commitment — not merely a lighter tint of
///   the same block (Sunsama's own finding: a tint-only task/event distinction reads as
///   "too subtle").
/// - A deadline is never a tile at all; see `DueMarkerRow`.
struct EventTile: View {
    let event: CalendarEvent
    /// The shared 60-sec clock (AppState.now) — drives the "passed" dim live as time elapses.
    let now: Date
    var compact: Bool = false
    /// Week-column density — smaller title type for the narrower columns.
    var dense: Bool = false
    /// Deadline-link state: glow this session, or push it back so the linked ones read.
    var emphasis: TileEmphasis = .none
    /// Check the underlying TASK off (the only checkbox there is).
    var onToggleTask: ((UUID) -> Void)? = nil
    /// Plan another session for a still-open task whose session has already passed.
    var onMoreTime: ((UUID) -> Void)? = nil

    /// A past session of a task that is still open — faded history that can grow more time.
    private var isPastOpenSession: Bool {
        event.isWorkBlock && !event.isHistory && event.end < now
    }

    var body: some View {
        HStack(spacing: 0) {
            accentBar
            HStack(alignment: .top, spacing: 4) {
                if event.isWorkBlock { taskCheckbox }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .atlasFont(size: dense ? 11 : 13, weight: .semibold, design: .rounded)
                        .strikethrough(event.isHistory)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    if !compact {
                        Text("\(event.timeLabel) · \(event.durationLabel)")
                            .atlasMono(size: 9)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    // A past session completes nothing — it's proof you worked. If its task
                    // is still open, this quiet affordance plans the NEXT session (one click).
                    // There is deliberately no session-level "done?" prompt, ever.
                    if isPastOpenSession, !compact, let onMoreTime {
                        Button { onMoreTime(event.id) } label: {
                            Text("+ more time")
                                .atlasMono(size: 9, weight: .bold)
                                .foregroundStyle(AtlasTheme.Colors.accentText)
                        }
                        .buttonStyle(.plain)
                        .help("Plan another session for this task")
                    }
                }
                Spacer(minLength: 0)
                // Read-only source glyph — indicates external / Apple Calendar origin
                if event.isReadOnly {
                    Image(systemName: "lock.fill")
                        .atlasFont(size: 9, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.top, compact ? 1 : 3)
                }
            }
            .padding(.leading, event.isWorkBlock ? 8 : 6)
            .padding(.trailing, 4)
            .padding(.vertical, compact ? 2 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileAccentColor.opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous))
        // Events sit borderless on their solid fill; a work session wears a 1.5 pt
        // full-strength dashed outline instead (and no left bar).
        .overlay {
            if event.isWorkBlock {
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                    .strokeBorder(tileAccentColor.opacity(event.isHistory ? 0.3 : 1),
                                  style: StrokeStyle(lineWidth: AtlasTheme.rule, dash: [4, 3]))
            }
        }
        // The glow half of the deadline↔work link: the sessions that serve the hovered due
        // date get a ring in their own class color (never a state color).
        .overlay {
            if emphasis == .glowing {
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                    .strokeBorder(tileAccentColor, lineWidth: 2)
            }
        }
        .shadow(color: emphasis == .glowing ? tileAccentColor.opacity(0.35) : .clear, radius: 6)
        .opacity(tileOpacity)
        .animation(.easeOut(duration: 0.15), value: emphasis)
    }

    /// A solid class-color bar for a real event. A work session carries its dashed outline
    /// instead and gets NO bar — never both.
    @ViewBuilder
    private var accentBar: some View {
        if !event.isWorkBlock {
            Rectangle()
                .fill(tileAccentColor)
                .frame(width: 3)
        }
    }

    /// The ONLY checkbox in the time model: it completes the TASK. Checking here fades this
    /// session into history and clears the task's future sessions; it never "completes" a
    /// session on its own.
    private var taskCheckbox: some View {
        Button { onToggleTask?(event.id) } label: {
            Image(systemName: event.isHistory ? "checkmark.square.fill" : "square")
                .atlasFont(size: 12, weight: .medium)
                .foregroundStyle(tileAccentColor)
                .padding(.top, compact ? 0 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(event.isHistory ? "Mark not done" : "Mark done")
    }

    private var tileAccentColor: Color {
        event.rendersNeutral ? AtlasTheme.Colors.textSecondary : event.color
    }

    /// Work sessions read as provisional (7 % wash under a dashed border); events sit on the
    /// solid 13 % class wash (`AtlasTheme.wash`). History is fainter still — present, but
    /// clearly behind you.
    private var backgroundOpacity: Double {
        if event.isHistory { return 0.05 }
        if event.isWorkBlock { return 0.07 }
        return event.isReadOnly ? 0.08 : 0.13
    }

    /// Elapsed tiles read as "passed" (dim only, no recolor); history is dimmer again; a
    /// dimmed tile is one the active deadline link pushed back.
    private var tileOpacity: Double {
        if emphasis == .dimmed { return 0.28 }
        if event.isHistory { return 0.5 }
        return event.end < now ? 0.65 : 1
    }

    private var titleColor: Color {
        if event.isHistory { return AtlasTheme.Colors.textMuted }
        return event.rendersNeutral ? AtlasTheme.Colors.textSecondary : AtlasTheme.Colors.textPrimary
    }
}

// MARK: - Due marker (rule — a deadline is a boundary, never an occupancy)

/// A due-date marker on the grid: a class-colored RULE drawn all the way across the day
/// column at the due time, carrying the label that says what is due.
///
/// It is deliberately not a block: a deadline occupies no time, it ends time.
///
/// **Two shapes.** A TIMED due keeps its own hairline plus a small paper-backed mono chip at
/// its exact time; near-simultaneous ones arrive as one group and their chips step up a row
/// so they stack instead of overprinting.
///
/// The END-OF-DAY row is different, and is where the old form fell apart: untimed dues (and
/// anything clamped to 11:59 PM) all park on the same y, so the day ended in a stack of
/// grid-wide "DUE <long title> No time planned" mono lines — the loudest thing on a calendar
/// whose actual content is quieter. That row now renders as ONE width-capped card anchored to
/// the right edge above a single hairline: a mono count header, then one compact
/// dot · title · time line per due, truncated to the card, collapsing past three with a
/// "+N more" toggle. Red is spent only on something genuinely past its deadline; everything
/// else wears ink. History markers ("was due", after a late reschedule) sit quietly at the
/// bottom of the list, muted and faded — never a grid-wide strikethrough.
///
/// Hovering (or clicking to pin) a title lights up that task's work sessions and dims
/// everything else — the deadline↔work link, unchanged in both shapes.
struct DueMarkerRow: View {
    let group: DueMarkerGroup
    /// Shared 60-sec clock — the only thing that can earn red here (past its deadline, still open).
    let now: Date
    /// The day column's width, so the end-of-day card caps itself instead of letting a long
    /// title run the whole grid.
    let columnWidth: CGFloat
    let linkedTaskID: UUID?
    var plannedLabel: ((UUID) -> String)? = nil
    var onLinkTask: ((UUID?) -> Void)? = nil

    /// End-of-day list expanded past the collapsed cap.
    @State private var expanded = false

    /// How many dues the card lists before it collapses the rest behind "+N more".
    static let collapsedLimit = 3

    /// Roughly how far the end-of-day card rises above its rule — header + up to
    /// `collapsedLimit` lines + chrome. The sticky "due later tonight" pill subtracts this so
    /// it stops claiming a marker is below the fold once its card is on screen.
    static func endOfDayCardHeight(_ group: DueMarkerGroup) -> CGFloat {
        let rows = min(group.count, collapsedLimit) + (group.count > collapsedLimit ? 1 : 0)
        return 12 + CGFloat(rows) * 16 + 13
    }

    /// The parked 11:59 PM row — the one that gets the card treatment.
    private var isEndOfDay: Bool { group.y == CalendarLayout.endOfDayY }

    var body: some View {
        if isEndOfDay {
            endOfDayCluster
        } else {
            timedMarkers
        }
    }

    // MARK: Timed dues — unchanged hairline + chip

    private var timedMarkers: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(group.deadlines.enumerated()), id: \.element.id) { index, dl in
                marker(for: dl, index: index)
            }
        }
        .frame(height: CalendarLayout.deadlineLabelHeight)
    }

    /// Row-local Y of one deadline's rule. Untimed (and end-of-day) dues share the parked
    /// row; timed ones sit at their own exact time, which is why a cluster keeps separate
    /// rules. Uses the clamped `deadlineMarkerY` so no rule draws past the grid's bottom.
    private func ruleY(for dl: CalendarEvent) -> CGFloat {
        let half = CalendarLayout.deadlineLabelHeight / 2
        return deadlineMarkerY(dl) - group.y + half
    }

    private func marker(for dl: CalendarEvent, index: Int) -> some View {
        let taskID = dl.deadlineTaskID
        let linked = taskID != nil && taskID == linkedTaskID
        let y = ruleY(for: dl)
        let step = CalendarLayout.deadlineLabelHeight
        return ZStack(alignment: .topTrailing) {
            // The rule itself never takes hits — it crosses the whole column, and an
            // invisible band across the grid would swallow taps and drags on the blocks
            // beneath it. Only the small chip is interactive.
            Rectangle()
                .fill(dl.color.opacity(linked ? 1 : 0.75))
                .frame(height: linked ? 2 : AtlasTheme.rule)
                .allowsHitTesting(false)
                .offset(y: y)
            chip(for: dl, taskID: taskID)
                .offset(x: -5, y: y - step / 2 - CGFloat(index) * step)
        }
    }

    private func chip(for dl: CalendarEvent, taskID: UUID?) -> some View {
        HStack(spacing: 4) {
            if !dl.hasSpecificTime {
                // "No time" glyph — this is due today, but no clock time was ever given.
                Image(systemName: "clock.badge.questionmark").atlasFont(size: 8, weight: .bold)
            }
            Text("DUE \(dl.title)")
                .atlasMono(size: 9, weight: .semibold)
                .lineLimit(1)
            if let taskID, let plannedLabel {
                Text(plannedLabel(taskID))
                    .atlasMono(size: 9, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(dl.color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        // Paper-backed so the chip knocks its own rule out behind it.
        .background(AtlasTheme.Colors.bgBase.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .fixedSize()
        .contentShape(Rectangle())
        .onHover { inside in
            guard let taskID else { return }
            onLinkTask?(inside ? taskID : nil)
        }
        .onTapGesture {
            guard let taskID else { return }
            onLinkTask?(linkedTaskID == taskID ? nil : taskID)
        }
        .help(dl.hasSpecificTime ? "Due" : "Due today — no time given")
    }

    // MARK: End-of-day cluster — one card, not a stack of grid-wide lines

    /// Live (still-open) dues first, oldest first; history sinks to the bottom.
    private var ordered: [CalendarEvent] {
        group.deadlines.sorted { a, b in
            if a.isHistory != b.isHistory { return !a.isHistory }
            return a.start < b.start
        }
    }

    private var live: [CalendarEvent] { group.deadlines.filter { !$0.isHistory } }

    private var visible: [CalendarEvent] {
        expanded ? ordered : Array(ordered.prefix(Self.collapsedLimit))
    }

    private var hiddenCount: Int { max(0, ordered.count - Self.collapsedLimit) }

    private func isOverdue(_ dl: CalendarEvent) -> Bool { !dl.isHistory && dl.end < now }

    /// Red is earned only by something actually past its deadline and still open; otherwise
    /// the card's chrome is ink, not a state color.
    private var chromeColor: Color {
        group.deadlines.contains(where: isOverdue) ? AtlasTheme.Colors.danger
                                                   : AtlasTheme.Colors.textSecondary
    }

    /// Times are listed only when the row actually mixes clock times in — otherwise the
    /// header already said everything a per-row "no time" could.
    private var showsTimes: Bool { live.contains(where: \.hasSpecificTime) }

    private var headerText: String {
        let n = live.count
        guard n > 0 else { return "WAS DUE TODAY" }
        return showsTimes ? "\(n) DUE BY 11:59 PM" : "\(n) DUE TODAY"
    }

    private var cardWidth: CGFloat { min(230, max(110, columnWidth - 12)) }

    /// A fixed-height spacer carrying the hairline at the row's center (= `group.y`); the card
    /// is an overlay so it can grow UPWARD off the parked bottom row without moving the rule.
    private var endOfDayCluster: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: CalendarLayout.deadlineLabelHeight)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(chromeColor.opacity(0.3))
                    .frame(height: AtlasTheme.hairlineWidth)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                card.offset(x: -6, y: -CalendarLayout.deadlineLabelHeight / 2 - 3)
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "flag.fill").atlasFont(size: 8, weight: .bold)
                Text(headerText).atlasMono(size: 9, weight: .bold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(chromeColor)
            ForEach(visible) { dl in
                dueLine(for: dl)
            }
            if hiddenCount > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "+\(hiddenCount) more")
                        .atlasMono(size: 9, weight: .bold)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(width: cardWidth, alignment: .leading)
        .background(AtlasTheme.Colors.bgBase,
                    in: RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
            .strokeBorder(chromeColor.opacity(0.45), lineWidth: AtlasTheme.hairlineWidth))
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }

    private func dueLine(for dl: CalendarEvent) -> some View {
        let taskID = dl.deadlineTaskID
        let linked = taskID != nil && taskID == linkedTaskID
        return HStack(spacing: 5) {
            Group {
                if dl.isHistory {
                    Image(systemName: "clock.arrow.circlepath")
                        .atlasFont(size: 8, weight: .bold)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                } else {
                    Circle().fill(dl.color).frame(width: 5, height: 5)
                }
            }
            .frame(width: 9)
            Text(dl.title)
                .atlasFont(size: 11, weight: linked ? .bold : .medium, design: .rounded)
                .foregroundStyle(lineColor(dl))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let trailing = trailingLabel(dl) {
                Text(trailing)
                    .atlasMono(size: 9, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize()
            }
        }
        .opacity(dl.isHistory ? 0.6 : 1)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .background(linked ? AtlasTheme.wash(dl.color) : .clear,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .onHover { inside in
            guard let taskID else { return }
            onLinkTask?(inside ? taskID : nil)
        }
        .onTapGesture {
            guard let taskID else { return }
            onLinkTask?(linkedTaskID == taskID ? nil : taskID)
        }
        .help(helpText(dl))
    }

    private func lineColor(_ dl: CalendarEvent) -> Color {
        if dl.isHistory { return AtlasTheme.Colors.textMuted }
        return isOverdue(dl) ? AtlasTheme.Colors.danger : AtlasTheme.Colors.textPrimary
    }

    private func trailingLabel(_ dl: CalendarEvent) -> String? {
        if dl.isHistory { return "was due" }
        guard showsTimes else { return nil }
        return dl.hasSpecificTime ? dl.timeLabel : "no time"
    }

    /// The full title and the planned-time readout live here, so the card itself stays a
    /// scannable list instead of a wall of mono text.
    private func helpText(_ dl: CalendarEvent) -> String {
        var parts = [dl.title]
        if dl.isHistory {
            parts.append("Was due here — rescheduled")
        } else {
            parts.append(dl.hasSpecificTime ? "Due \(dl.timeLabel)" : "Due today — no time given")
        }
        if let taskID = dl.deadlineTaskID, let plannedLabel {
            let planned = plannedLabel(taskID)
            if !planned.isEmpty { parts.append(planned) }
        }
        return parts.joined(separator: " · ")
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
                        .atlasFont(size: 9)
                        .foregroundStyle(dl.color)
                    Text(dl.title)
                        .atlasFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    if dl.hasSpecificTime {
                        Spacer(minLength: 12)
                        Text(dl.timeLabel)
                            .atlasMono(size: 11, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180, alignment: .leading)
    }
}

// MARK: - Day view (gutter + one column)

/// Publishes the day grid's live scroll offset so the sticky "due later tonight" edge-chip
/// knows which due markers have fallen below the viewport.
private struct DayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DayCalendarView: View {
    let date: Date
    let events: [CalendarEvent]
    /// Shared 60-sec clock (AppState.now), forwarded down so past tiles dim live.
    let now: Date
    var onTapEmpty: ((Date, Double) -> Void)? = nil
    var onTapEvent: ((CalendarEvent) -> Void)? = nil
    var onDragEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    var onDropEvent: ((CalendarEvent, CGPoint) -> Void)? = nil
    var linkedTaskID: UUID? = nil
    var onLinkTask: ((UUID?) -> Void)? = nil
    var onToggleTask: ((UUID) -> Void)? = nil
    var onMoreTime: ((UUID) -> Void)? = nil
    var plannedLabel: ((UUID) -> String)? = nil

    /// How far the grid is scrolled, in content points.
    @State private var scrollOffset: CGFloat = 0
    /// Height of the visible grid area.
    @State private var viewportHeight: CGFloat = 0

    /// Top padding inside the scroll content — due-marker Y values are offset by it.
    private static let contentTopInset: CGFloat = 6

    private var markers: [DueMarkerGroup] { dueMarkerGroups(events.filter(\.isDeadline)) }

    /// Due markers that have fallen below the visible grid — what the edge-chip counts.
    /// Late-evening and untimed dues (which park at 11:59 PM) are exactly the ones a
    /// scrolled-to-now grid hides, and exactly the ones you must not miss.
    private var belowViewport: [DueMarkerGroup] {
        guard viewportHeight > 0 else { return [] }
        let bottom = scrollOffset + viewportHeight
        // Measure the row's TOP edge, not its rule: the label draws ABOVE the rule, so a
        // marker whose label is fully on screen must not still claim to be below the fold
        // (which left the pill lying at the bottom of the day, with nothing to scroll to).
        // The end-of-day row's label is a card, which rises further than a chip does.
        return markers.filter { group in
            let label = group.y == CalendarLayout.endOfDayY
                ? DueMarkerRow.endOfDayCardHeight(group)
                : CalendarLayout.deadlineLabelHeight / 2
            return group.y - label + Self.contentTopInset >= bottom
        }
    }

    /// All-day items ride the strip above the grid, never the column — an all-day event is a
    /// day label, not an occupancy. Deadlines are excluded: their hairline markers inside the
    /// column already say what's due, and the week view's "N due" cap is a jump target that
    /// would do nothing here.
    private var stripEvents: [CalendarEvent] {
        events.filter { $0.isAllDay && !$0.isDeadline }
    }

    /// Height the strip takes out of the scroll viewport (0 when it renders nothing) — the
    /// below-the-fold due count is measured against the grid, not the whole pane.
    private var stripHeight: CGFloat {
        stripEvents.isEmpty ? 0 : CalendarLayout.allDayRowHeight + 4
    }

    var body: some View {
        GeometryReader { outer in
            VStack(spacing: 0) {
                AllDayRowView(
                    days: [date],
                    columnWidth: max(0, outer.size.width - CalendarLayout.gutterWidth - 6 - 8),
                    now: now,
                    eventsProvider: { _ in stripEvents }
                )
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
                                    onDropEvent: onDropEvent,
                                    linkedTaskID: linkedTaskID,
                                    onLinkTask: onLinkTask,
                                    onToggleTask: onToggleTask,
                                    onMoreTime: onMoreTime,
                                    plannedLabel: plannedLabel
                                )
                            }
                            .padding(.trailing, 8)
                            .padding(.top, Self.contentTopInset)
                            .padding(.bottom, 16)

                            // Zero-height sentinel anchored at the current-time Y so that
                            // scrollTo("nowAnchor", anchor: .center) lands precisely on "now".
                            nowSentinel
                            // Anchor at the first below-the-fold due marker — the edge-chip's
                            // jump target.
                            if let first = belowViewport.first {
                                dueSentinel(at: first.y - CalendarLayout.deadlineLabelHeight / 2)
                            }
                        }
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: DayScrollOffsetKey.self,
                                    value: -g.frame(in: .named("dayGridScroll")).minY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "dayGridScroll")
                    .onPreferenceChange(DayScrollOffsetKey.self) { scrollOffset = $0 }
                    .onAppear {
                        viewportHeight = outer.size.height - stripHeight
                        scrollToNowIfVisible(proxy: proxy)
                    }
                    .onChange(of: outer.size.height) { _, h in viewportHeight = h - stripHeight }
                    .onChange(of: stripHeight) { _, h in viewportHeight = outer.size.height - h }
                    // Sticky bottom edge-chip: due markers exist below the fold. Nothing is
                    // hidden or collapsed — the chip is a nudge plus a jump, and the markers
                    // themselves stay the source of truth.
                    .overlay(alignment: .bottom) {
                        if !belowViewport.isEmpty {
                            DueBelowChip(count: belowViewport.reduce(0) { $0 + $1.count }) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("dueAnchor", anchor: .center)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
    }

    /// Layout-positioned anchor (an `.offset` is visual-only and would land scrollTo at y=0).
    private func dueSentinel(at y: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: 1, height: max(0, y + Self.contentTopInset))
            Color.clear.frame(width: 1, height: 1).id("dueAnchor")
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

/// The sticky bottom edge-chip: "2 due later tonight ↓". Appears only while due markers sit
/// below the viewport (a grid auto-scrolled to "now" hides 11:59 PM by definition). Clicking
/// scrolls to the first one. It never collapses or replaces the markers — it points at them.
struct DueBelowChip: View {
    let count: Int
    let onJump: () -> Void

    var body: some View {
        Button(action: onJump) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").atlasFont(size: 9, weight: .bold)
                Text(count == 1 ? "1 due later tonight" : "\(count) due later tonight")
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
                Image(systemName: "arrow.down").atlasFont(size: 9, weight: .bold)
            }
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AtlasTheme.Colors.bgBase, in: Capsule())
            .overlay(Capsule().strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Jump to what's due later today")
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
    var linkedTaskID: UUID? = nil
    var onLinkTask: ((UUID?) -> Void)? = nil
    var onToggleTask: ((UUID) -> Void)? = nil
    var onMoreTime: ((UUID) -> Void)? = nil
    var plannedLabel: ((UUID) -> String)? = nil
    /// The due-count cap's jump target — opens that day in Day view.
    var onJumpToDay: ((Date) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            // columnWidth accounts for all fixed chrome around the day columns: the hour
            // gutter + its 6 pt trailing padding, the VStack's 8 pt trailing padding, and
            // the (days.count - 1) 1 pt column dividers.
            let columnWidth = (geo.size.width - CalendarLayout.gutterWidth - 6 - 8
                               - CGFloat(days.count - 1)) / CGFloat(days.count)
            VStack(spacing: 0) {
                // ── Sticky weekday / date header ──────────────────────────────
                WeekColumnHeader(
                    days: days,
                    columnWidth: columnWidth,
                    deadlineCount: { eventsProvider($0).filter(\.isDeadline).count }
                )

                // ── All-day event strip (collapses to 0 height when empty) ────
                AllDayRowView(
                    days: days,
                    columnWidth: columnWidth,
                    now: now,
                    eventsProvider: eventsProvider,
                    onJumpToDay: { onJumpToDay?($0) }
                )

                // ── Scrollable time grid (auto-scrolls to current hour) ───────
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: 0) {
                                HourGutter(interval: 3)
                                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                    DayColumnView(
                                        date: day,
                                        events: eventsProvider(day),
                                        now: now,
                                        isToday: Calendar.current.isDateInToday(day),
                                        isWeek: true,
                                        onTapEmpty: onTapEmpty,
                                        onTapEvent: onTapEvent,
                                        onDragEvent: onDragEvent,
                                        onDropEvent: onDropEvent,
                                        linkedTaskID: linkedTaskID,
                                        onLinkTask: onLinkTask,
                                        onToggleTask: onToggleTask,
                                        onMoreTime: onMoreTime,
                                        plannedLabel: plannedLabel
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
