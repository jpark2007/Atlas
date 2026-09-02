import SwiftUI
import AtlasCore

/// Day / Week / Month / List segmented mode for the calendar.
enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case list = "List"
    var id: String { rawValue }
}

/// Time-grid geometry helper on the shared `CalendarEvent`.
extension CalendarEvent {
    var durationMinutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

// MARK: - Layout helpers

/// Shared geometry constants for the time grid.
enum CalendarLayout {
    static let startHour: Int = 0        // 12 AM — full-day grid; the view auto-scrolls to "now"
    static let endHour: Int = 24         // midnight (exclusive end → last row is the 11 PM slot)
    /// Working-hours window for auto-scheduling ("Suggest a time"). The grid spans the
    /// full day, but slot suggestions stay within waking hours rather than proposing 3 AM.
    static let workdayStartHour: Int = 7   // 7 AM
    static let workdayEndHour: Int = 22    // 10 PM
    static let hourHeight: CGFloat = 56
    static let gutterWidth: CGFloat = 54
    static let minEventHeight: CGFloat = 26
    /// Height of the all-day strip when it contains at least one event (Task 5 populates it).
    static let allDayRowHeight: CGFloat = 28
    /// Vertical space a timed-deadline label occupies on the grid. Deadlines whose lines fall
    /// within this many points collapse into one "N due" cluster chip so labels don't overprint.
    static let deadlineLabelHeight: CGFloat = 14

    static var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    /// Y position for an UNTIMED due marker — the very end of the day (11:59 PM), where a
    /// "due today, no time given" item honestly belongs. Inset by the label height so the
    /// row stays fully inside the clipped column.
    static var endOfDayY: CGFloat { totalHeight - deadlineLabelHeight }

    /// Fractional hours since `startHour` for a given date.
    static func offsetHours(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return CGFloat(h - startHour) + CGFloat(m) / 60
    }
}

/// An event with its column (lane) assignment for overlap-safe layout.
struct PositionedEvent: Identifiable {
    let event: CalendarEvent
    let lane: Int
    let laneCount: Int
    var id: UUID { event.id }
}

/// Greedy column packing: overlapping events are split into side-by-side lanes
/// so nothing is drawn on top of anything else.
func packEventsIntoLanes(_ events: [CalendarEvent]) -> [PositionedEvent] {
    let sorted = events.sorted { $0.start < $1.start }
    var result: [PositionedEvent] = []
    var cluster: [CalendarEvent] = []
    var clusterEnd: Date?

    func flush() {
        guard !cluster.isEmpty else { return }
        var laneEnds: [Date] = []
        var assigned: [(CalendarEvent, Int)] = []
        for ev in cluster {
            var placed = false
            for i in laneEnds.indices where laneEnds[i] <= ev.start {
                laneEnds[i] = ev.end
                assigned.append((ev, i))
                placed = true
                break
            }
            if !placed {
                laneEnds.append(ev.end)
                assigned.append((ev, laneEnds.count - 1))
            }
        }
        let count = max(1, laneEnds.count)
        for (ev, lane) in assigned {
            result.append(PositionedEvent(event: ev, lane: lane, laneCount: count))
        }
        cluster.removeAll()
        clusterEnd = nil
    }

    for ev in sorted {
        if let end = clusterEnd, ev.start < end {
            cluster.append(ev)
            clusterEnd = Swift.max(end, ev.end)
        } else {
            flush()
            cluster = [ev]
            clusterEnd = ev.end
        }
    }
    flush()
    return result
}

/// A run of timed deadlines close enough in time that their grid labels would overprint.
/// Nothing collapses: every deadline in a cluster keeps its own rule, and the labels step
/// up a row so they stack instead of overprinting.
struct DeadlineCluster: Identifiable {
    let events: [CalendarEvent]   // sorted by start, always ≥1
    var id: UUID { events[0].id }
    var representative: CalendarEvent { events[0] }   // earliest — drives the line's y position
    var count: Int { events.count }
}

/// Groups timed deadlines whose labels would overlap on the grid. Sorted by time; a new
/// cluster starts whenever the next deadline's line sits more than `gapPoints` below the
/// previous one. Pure (no view state) so it stays out of the type-check-heavy grid body.
func clusterTimedDeadlines(_ deadlines: [CalendarEvent], gapPoints: CGFloat) -> [DeadlineCluster] {
    let sorted = deadlines.sorted { $0.start < $1.start }
    var clusters: [DeadlineCluster] = []
    var current: [CalendarEvent] = []
    var lastY: CGFloat = 0
    for dl in sorted {
        let y = deadlineMarkerY(dl)
        if current.isEmpty || y - lastY <= gapPoints {
            current.append(dl)
        } else {
            clusters.append(DeadlineCluster(events: current))
            current = [dl]
        }
        lastY = y
    }
    if !current.isEmpty { clusters.append(DeadlineCluster(events: current)) }
    return clusters
}

// MARK: - Due markers (hairlines, never blocks)

/// One due-marker row on the grid: the deadlines that share a y position. Untimed dues (and
/// anything clamped to 11:59 PM) share the parked end-of-day row; each chip says for itself
/// whether it carries a real clock time.
struct DueMarkerGroup: Identifiable {
    let deadlines: [CalendarEvent]
    /// Points from the top of the grid.
    let y: CGFloat
    var id: UUID { deadlines[0].id }
    var count: Int { deadlines.count }
}

/// Grid Y for one deadline's rule, never below `endOfDayY`.
///
/// A date-only due resolves to 11:59:59 PM (`Task.effectiveDueDate`), which lands a pixel off
/// the bottom of the column: its chip clipped against the grid's edge and collided with the
/// sticky "due later tonight" pill. Clamping parks those on the same end-of-day row untimed
/// dues already use, so they cluster (and stack) with each other instead of overprinting.
func deadlineMarkerY(_ deadline: CalendarEvent) -> CGFloat {
    guard deadline.hasSpecificTime else { return CalendarLayout.endOfDayY }
    let y = CalendarLayout.offsetHours(for: deadline.start) * CalendarLayout.hourHeight
    return min(y, CalendarLayout.endOfDayY)
}

/// Splits a day's deadlines into marker rows.
///
/// Timed dues sit at their actual due time, grouped via `clusterTimedDeadlines` so
/// near-simultaneous labels can stack instead of overprinting. Untimed dues (a bare date, i.e. local
/// midnight) collect into ONE row parked at the end of the day — they aren't "due at
/// 12 AM", they're "due today, no time given", which the row's glyph says out loud.
func dueMarkerGroups(_ deadlines: [CalendarEvent]) -> [DueMarkerGroup] {
    let timed = deadlines.filter(\.hasSpecificTime)
    let untimed = deadlines.filter { !$0.hasSpecificTime }
    var rows = clusterTimedDeadlines(timed, gapPoints: CalendarLayout.deadlineLabelHeight)
        .map { cluster in
            DueMarkerGroup(deadlines: cluster.events, y: deadlineMarkerY(cluster.representative))
        }
    guard !untimed.isEmpty else { return rows }
    // Untimed dues share the parked end-of-day row — and so does anything clamped there
    // (an 11:59 PM due). Merge instead of stacking a second row on the same y, which
    // would overprint one set of chips on the other.
    if let i = rows.firstIndex(where: { $0.y == CalendarLayout.endOfDayY }) {
        rows[i] = DueMarkerGroup(deadlines: rows[i].deadlines + untimed, y: CalendarLayout.endOfDayY)
    } else {
        rows.append(DueMarkerGroup(deadlines: untimed, y: CalendarLayout.endOfDayY))
    }
    return rows
}

/// Cached formatters for the grid chrome (gutter, headers).
enum CalendarFormat {
    static let hour: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    /// "MON AUG 24" — the header's mono day label.
    static let monoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()
    /// "AUG 24" — one end of the header's mono week range.
    static let monoMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    /// "24" — the closing end of a same-month week range.
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
}
