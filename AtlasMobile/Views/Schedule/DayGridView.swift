import SwiftUI
import AtlasCore

/// A real hour grid for one day (spec §4.1 / Wave-3 Task 6). A 24 h proportional
/// canvas: a 66 pt left rail of hour labels + hairline rules, space-tinted blocks
/// for events and scheduled tasks laid out in greedy overlap columns, red deadline
/// lines for clock-timed due tasks, an all-day chip row pinned above the scroll,
/// and a clay NOW line (today) with auto-scroll. Also hosts the drag-to-place chip.
struct DayGridView: View {
    let day: Date
    let now: Date
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    let onOpen: (ItemDetailSheet.Detail) -> Void
    let onToggle: (TaskItem) -> Void

    // Placement (only active when `placing != nil`). `placeMinutes` is the live
    // start time (minutes-from-midnight, snapped to 15) the chip rides at.
    var placing: TaskItem? = nil
    @Binding var placeMinutes: Int
    var onConfirmPlace: () -> Void = {}
    var onCancelPlace: () -> Void = {}

    // Block-move (Task H). `blockMoveActive` mirrors `placing != nil` for the FAB:
    // it hides the ScheduleView FAB while a block is lifted. The two closures write
    // the new time through the existing store paths (task: scheduledAt; event: shift
    // start+end by the same delta, googleEventId preserved).
    @Binding var blockMoveActive: Bool
    var onMoveTask: (TaskItem, Int) -> Void = { _, _ in }
    var onMoveEvent: (CalendarEvent, Int) -> Void = { _, _ in }

    private let hourHeight: CGFloat = 56
    private let railWidth: CGFloat = 66
    private let minBlockHeight: CGFloat = 26
    private let gutter: CGFloat = 4
    private let cal = Calendar.current

    @State private var dragBase: Int?

    // Block-move state: `armedID` is the lifted block (nil = none). `moveMinutes` is
    // its live start (snapped to 15, clamped like the placement chip); `moveBase`
    // seeds the drag from the block's original start.
    @State private var armedID: UUID?
    @State private var moveMinutes = 0
    @State private var moveBase: Int?

    private var canvasHeight: CGFloat { hourHeight * 24 }
    private var dayStart: Date { cal.startOfDay(for: day) }
    private var isToday: Bool { cal.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty { allDayRow }
            gridScroll
        }
        .overlay(alignment: .bottomTrailing) {
            if placing != nil { placementControls }
            else if armedID != nil { moveControls }
        }
    }

    // MARK: - All-day chips (pinned above the scroll)

    private var allDayEvents: [CalendarEvent] {
        events.filter { $0.isAllDay && overlapsDay($0.start, $0.end) }
    }

    private var allDayRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allDayEvents) { ev in
                    Button { onOpen(.event(ev)) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(ev.color).frame(width: 7, height: 7)
                            Text(ev.title)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(MobileTheme.ink)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                            .fill(ev.color.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(MobileTheme.hairline).frame(height: 1) }
    }

    // MARK: - Scrolling grid

    private var gridScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GeometryReader { geo in
                    canvas(width: geo.size.width)
                }
                .frame(height: canvasHeight)
            }
            .contentMargins(.bottom, 300, for: .scrollContent)
            .onAppear { scrollToStart(proxy) }
        }
    }

    private func canvas(width: CGFloat) -> some View {
        let blocks = layout(width: width)
        return ZStack(alignment: .topLeading) {
            hourColumn(width: width)                                   // rail + rules (real layout = scroll anchors)
            ForEach(blocks) { blockView($0) }
            ForEach(deadlines) { deadlineMarker($0, width: width) }
            if isToday { nowLine(width: width) }
            placementChip(width: width)
        }
        .frame(width: width, height: canvasHeight, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    /// Hour rail + rules. Each hour is a real 56 pt row so `ScrollViewReader` can
    /// scroll to it (offset-positioned overlays don't carry layout position).
    private func hourColumn(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                        .frame(width: railWidth - 8, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(MobileTheme.hairline).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .frame(width: width, height: canvasHeight, alignment: .topLeading)
    }

    // MARK: - Blocks

    @ViewBuilder
    private func blockView(_ blk: Block) -> some View {
        let armed = blk.id == armedID
        // When armed, the block rides `moveMinutes` (like the placement chip);
        // duration is fixed, so height stays derived from the original interval.
        let y = CGFloat(armed ? moveMinutes : blk.startMin) * hourHeight / 60
        let h = max(CGFloat(blk.endMin - blk.startMin) * hourHeight / 60, minBlockHeight)
        let base = HStack(alignment: .center, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(blk.color).frame(width: 3, height: max(6, h - 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let task = blk.task {
                        // Suppress the check-off while this block is lifted.
                        CheckCircle(done: task.done, color: task.spaceColor) { if !armed { onToggle(task) } }
                    }
                    Text(blk.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(blk.task?.done == true ? MobileTheme.faint : MobileTheme.ink)
                        .strikethrough(blk.task?.done == true, color: MobileTheme.faint)
                        .lineLimit(1)
                }
                if h >= 44 {
                    Text(armed ? caps(minute: moveMinutes) : timeCaps(blk))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.7).textCase(.uppercase)
                        .foregroundStyle(armed ? MobileTheme.accentText : MobileTheme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(width: blk.w, height: h, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(blk.color.opacity(0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .scaleEffect(armed ? 1.03 : 1, anchor: .center)
        .shadow(color: Color.black.opacity(armed ? 0.18 : 0), radius: armed ? 8 : 0, y: armed ? 3 : 0)
        .contentShape(Rectangle())
        // Tap opens the detail sheet — but not while the block is armed for a move.
        .onTapGesture { if !armed { onOpen(blk.detail) } }
        .offset(x: blk.x, y: y)
        .zIndex(armed ? 1 : 0)

        // Gesture wiring is the whole scroll-safety story: only the ARMED block gets a
        // drag (highPriority, so it wins over the ScrollView); un-armed WRITABLE blocks
        // carry only a long-press (a moving finger cancels it, so pans still scroll);
        // read-only blocks get nothing.
        if armed {
            base.highPriorityGesture(moveDrag(blk))
        } else if isWritable(blk) {
            base.onLongPressGesture(minimumDuration: 0.4) { arm(blk) }
        } else {
            base
        }
    }

    // MARK: - Block-move (long-press lift → drag → confirm/cancel)

    /// Writability mirrors `ItemDetailSheet.isEditable` verbatim (CLAUDE.md rule 5):
    /// tasks always; events only when Atlas- or Google-sourced. Read-only events
    /// (Apple, and any external read-only) never lift.
    private func isWritable(_ blk: Block) -> Bool {
        switch blk.detail {
        case .task:          return true
        case .event(let e):  return e.source == .atlas || e.source == .google
        }
    }

    /// Long-press arms a move: haptic tap + lifted look. Blocked while a placement
    /// chip is live or another block is already armed (mutual exclusion).
    private func arm(_ blk: Block) {
        guard placing == nil, armedID == nil else { return }
        moveMinutes = blk.startMin
        moveBase = nil
        MobileTheme.Haptic.selection()
        blockMoveActive = true
        withAnimation(MobileTheme.spring) { armedID = blk.id }
    }

    /// Chip-style vertical drag for the armed block — same delta→snap-15→clamp math
    /// as `placementDrag`, seeded from the block's original start.
    private func moveDrag(_ blk: Block) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = moveBase ?? blk.startMin
                if moveBase == nil { moveBase = base }
                let delta = Int((value.translation.height / hourHeight) * 60)
                var m = base + delta
                m = Int((Double(min(max(m, 0), 1425)) / 15).rounded()) * 15   // snap to 15 min
                moveMinutes = min(max(m, 0), 1425)                            // clamp 00:00–23:45
            }
            .onEnded { _ in
                moveBase = nil
                MobileTheme.Haptic.selection()
            }
    }

    private var moveControls: some View {
        HStack(spacing: 14) {
            Button { cancelMove() } label: { placeCircle("xmark") }
            Button { confirmMove() } label: { placeCircle("checkmark") }
        }
        .padding(.trailing, 24).padding(.bottom, 96)
    }

    /// Confirm writes the new time through the existing store path: a task gets its
    /// `scheduledAt` set (mirrors `confirmPlace`); an event shifts start+end by the
    /// same delta (duration + googleEventId preserved). Both run in ScheduleView.
    private func confirmMove() {
        guard let id = armedID, let blk = rawBlocks().first(where: { $0.id == id }) else {
            cancelMove(); return
        }
        if let task = blk.task {
            onMoveTask(task, moveMinutes)
        } else if case .event(let e) = blk.detail {
            onMoveEvent(e, moveMinutes - blk.startMin)
        }
        MobileTheme.Haptic.success()
        blockMoveActive = false
        withAnimation(MobileTheme.spring) { armedID = nil }
    }

    /// Cancel restores the original position (armed clears → block renders at its
    /// stored start again); no write.
    private func cancelMove() {
        moveBase = nil
        blockMoveActive = false
        withAnimation(MobileTheme.spring) { armedID = nil }
    }

    // MARK: - Deadlines (clock-timed due tasks → red line + flag + caps title)

    private struct Deadline: Identifiable {
        let task: TaskItem
        let minute: Int
        var id: UUID { task.id }
    }

    private var deadlines: [Deadline] {
        tasks.compactMap { t in
            guard !t.done, t.scheduledAt == nil, let due = t.dueDate,
                  cal.isDate(due, inSameDayAs: day), hasClockTime(due) else { return nil }
            return Deadline(task: t, minute: clampMin(minutesFromStart(due)))
        }
    }

    private func deadlineMarker(_ d: Deadline, width: CGFloat) -> some View {
        let y = CGFloat(d.minute) * hourHeight / 60
        return VStack(alignment: .trailing, spacing: 2) {
            Text(d.task.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6).textCase(.uppercase)
                .foregroundStyle(AtlasTheme.Colors.danger)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AtlasTheme.Colors.danger)
                Rectangle().fill(AtlasTheme.Colors.danger).frame(height: 1.5)
            }
        }
        .frame(width: max(0, width - railWidth - 12), alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(.task(d.task)) }
        .offset(x: railWidth, y: y - 16)
    }

    // MARK: - NOW line (today only)

    private func nowLine(width: CGFloat) -> some View {
        let y = CGFloat(clampMin(minutesFromStart(now))) * hourHeight / 60
        return HStack(spacing: 0) {
            Circle().fill(MobileTheme.accent).frame(width: 7, height: 7)
            Rectangle().fill(MobileTheme.accent).frame(height: 2)
        }
        .frame(width: max(0, width - railWidth + 4))
        .offset(x: railWidth - 4, y: y - 1)
        .allowsHitTesting(false)   // decorative — must not steal taps from blocks beneath
    }

    // MARK: - Placement chip + controls

    @ViewBuilder
    private func placementChip(width: CGFloat) -> some View {
        if let task = placing {
            let y = CGFloat(placeMinutes) * hourHeight / 60
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(task.spaceColor).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .lineLimit(1)
                    Text(caps(minute: placeMinutes))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.88).textCase(.uppercase)
                        .foregroundStyle(MobileTheme.accentText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(width: max(0, width - railWidth - 12), height: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MobileTheme.bg))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(task.spaceColor.opacity(0.6), lineWidth: MobileTheme.rule))
            .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
            .offset(x: railWidth, y: y)
            .highPriorityGesture(placementDrag)
        }
    }

    private var placementDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                let base = dragBase ?? placeMinutes
                if dragBase == nil { dragBase = base }
                let delta = Int((value.translation.height / hourHeight) * 60)
                var m = base + delta
                m = Int((Double(min(max(m, 0), 1425)) / 15).rounded()) * 15   // snap to 15 min
                placeMinutes = min(max(m, 0), 1425)                            // clamp 00:00–23:45
            }
            .onEnded { _ in
                dragBase = nil
                MobileTheme.Haptic.selection()
            }
    }

    private var placementControls: some View {
        HStack(spacing: 14) {
            Button { onCancelPlace() } label: { placeCircle("xmark") }
            Button { onConfirmPlace() } label: { placeCircle("checkmark") }
        }
        .padding(.trailing, 24).padding(.bottom, 96)
    }

    private func placeCircle(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(MobileTheme.ink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(MobileTheme.bg))
            .overlay(Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
    }

    // MARK: - Layout (blocks + greedy overlap columns)

    private struct Block: Identifiable {
        let id: UUID
        let detail: ItemDetailSheet.Detail
        let title: String
        let color: Color
        let startMin: Int
        let endMin: Int
        let task: TaskItem?
        var column = 0
        var columnCount = 1
        var x: CGFloat = 0
        var w: CGFloat = 0
    }

    private func rawBlocks() -> [Block] {
        var out: [Block] = []
        for ev in events where !ev.isAllDay && overlapsDay(ev.start, ev.end) {
            let s = clampMin(minutesFromStart(ev.start))
            let e = max(s + 1, clampMin(minutesFromStart(ev.end)))
            out.append(Block(id: ev.id, detail: .event(ev), title: ev.title,
                             color: ev.color, startMin: s, endMin: e, task: nil))
        }
        // Completed scheduled tasks STAY on the grid (fill + strikethrough via blockView)
        // — a done work-block is history, never an instant vanish (check-off contract).
        for t in tasks {
            guard let at = t.scheduledAt, cal.isDate(at, inSameDayAs: day) else { continue }
            let s = clampMin(minutesFromStart(at))
            let e = min(1440, s + (t.durationMin ?? 60))
            out.append(Block(id: t.id, detail: .task(t), title: t.title,
                             color: t.spaceColor, startMin: s, endMin: max(s + 1, e), task: t))
        }
        return out
    }

    /// Greedy interval-graph columns: sort by start; a run of mutually-overlapping
    /// blocks forms a cluster that shares the width equally. Within a cluster each
    /// block takes the first column whose previous block has already ended.
    private func layout(width: CGFloat) -> [Block] {
        let sorted = rawBlocks().sorted {
            $0.startMin != $1.startMin ? $0.startMin < $1.startMin : $0.endMin < $1.endMin
        }
        var result: [Block] = []
        var cluster: [Block] = []
        var colEnds: [Int] = []        // last endMin per column in the current cluster
        var clusterEnd = -1

        func flush() {
            let count = max(colEnds.count, 1)
            for var b in cluster { b.columnCount = count; result.append(b) }
            cluster.removeAll(); colEnds.removeAll()
        }

        for var b in sorted {
            if !cluster.isEmpty && b.startMin >= clusterEnd { flush(); clusterEnd = -1 }
            var placed = false
            for i in colEnds.indices where colEnds[i] <= b.startMin {
                b.column = i; colEnds[i] = b.endMin; placed = true; break
            }
            if !placed { b.column = colEnds.count; colEnds.append(b.endMin) }
            cluster.append(b)
            clusterEnd = clusterEnd == -1 ? b.endMin : max(clusterEnd, b.endMin)
        }
        flush()

        let available = max(0, width - railWidth - 12)
        return result.map { b in
            var bb = b
            let colWidth = available / CGFloat(b.columnCount)
            bb.x = railWidth + CGFloat(b.column) * colWidth
            bb.w = max(0, colWidth - gutter)
            return bb
        }
    }

    // MARK: - Auto-scroll

    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let targetHour: Int
        if isToday {
            targetHour = max(0, cal.component(.hour, from: now) - 2)
        } else if let first = rawBlocks().map(\.startMin).min() {
            targetHour = max(0, first / 60)
        } else {
            targetHour = 7
        }
        DispatchQueue.main.async {
            proxy.scrollTo(min(23, targetHour), anchor: .top)
        }
    }

    // MARK: - Helpers

    private func minutesFromStart(_ date: Date) -> Int {
        cal.dateComponents([.minute], from: dayStart, to: date).minute ?? 0
    }

    private func clampMin(_ m: Int) -> Int { min(1440, max(0, m)) }

    private func overlapsDay(_ start: Date, _ end: Date) -> Bool {
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return end > dayStart && start < dayEnd
    }

    private func hasClockTime(_ date: Date) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private func caps(minute: Int) -> String {
        let h = (minute / 60) % 24, m = minute % 60
        let date = cal.date(bySettingHour: h, minute: m, second: 0, of: dayStart) ?? dayStart
        let f = DateFormatter()
        f.dateFormat = m == 0 ? "h a" : "h:mm a"
        return f.string(from: date)
    }

    private func timeCaps(_ blk: Block) -> String {
        "\(caps(minute: blk.startMin)) – \(caps(minute: blk.endMin))"
    }
}
