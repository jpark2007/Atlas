import Foundation

/// Shared duration ladder + labels for the mobile event pickers (`ManualAddSheet`,
/// `ItemDetailSheet`). The ladder used to stop at 120 min, which silently truncated
/// any longer event — a 3-hour Google/ICS event opened with no matching entry, and
/// picking anything rewrote `end` to ≤2h. It now runs to a full day, and
/// `options(including:)` keeps an off-ladder length (say 275 min) selectable.
enum EventDuration {

    /// Coarsening steps: quarter-hours through 2h, half-hours to 4h, then hours.
    static let ladder: [Int] = [15, 30, 45, 60, 90, 120, 150, 180, 210, 240,
                                300, 360, 420, 480, 540, 600, 660, 720, 1440]

    /// The ladder with `current` folded in (in order) when it isn't already a rung,
    /// so an event's real length is always a selectable, checkmarked option.
    static func options(including current: Int) -> [Int] {
        ladder.contains(current) ? ladder : (ladder + [current]).sorted()
    }

    /// "45 min" · "1 hr" · "1 hr 30 min" · "All day" (exactly 24h).
    static func label(_ minutes: Int) -> String {
        if minutes == 1440 { return "All day" }
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _):  return "\(m) min"
        case (_, 0):  return "\(h) hr"
        default:      return "\(h) hr \(m) min"
        }
    }
}
