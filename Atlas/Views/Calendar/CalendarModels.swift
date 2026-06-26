import SwiftUI
import UniformTypeIdentifiers

/// Day / Week segmented mode for the calendar.
enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    var id: String { rawValue }
}

/// Time-grid geometry helper on the shared `CalendarEvent`.
extension CalendarEvent {
    var durationMinutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

/// The drag payload carried from the tray to a time slot.
struct DraggableTaskID: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Layout helpers

/// Shared geometry constants for the time grid.
enum CalendarLayout {
    static let startHour: Int = 7        // 7 AM
    static let endHour: Int = 22         // 10 PM
    static let hourHeight: CGFloat = 56
    static let gutterWidth: CGFloat = 54
    static let minEventHeight: CGFloat = 26

    static var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

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
    static let fullDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
