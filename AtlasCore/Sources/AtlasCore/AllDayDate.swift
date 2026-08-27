import Foundation

/// The one place that knows how an all-day event is encoded.
///
/// **Timed events are absolute instants. All-day events are floating dates.** A 3pm meeting is
/// a moment in time and correctly shows at noon after flying to California; "Labor Day, Sept 7"
/// is not a moment in time and must read Sept 7 in Tokyo, in London, and on the plane.
///
/// Canonical encoding: **UTC midnight of the intended calendar date** — `2026-09-07T00:00:00Z`
/// means "Sept 7", full stop. (Chosen because three of four ingest paths already write it, and
/// because the server-side `google-sync` job has no user timezone to anchor a local midnight to.)
///
/// The corollary, and the reason this type exists: an all-day instant must be bucketed with a
/// **UTC** calendar. Read with `Calendar.current`, it lands on the previous day anywhere west of
/// Greenwich — which is exactly the day-off bug this fixes.
public enum AllDayDate {

    /// A gregorian calendar pinned to UTC — the frame all-day instants are written in.
    public static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    /// The UTC calendar date `instant` names, as a UTC start-of-day. Two all-day copies of the
    /// same holiday are the same event exactly when this matches.
    public static func utcDay(of instant: Date) -> Date {
        utc.startOfDay(for: instant)
    }

    /// The same calendar date, re-anchored to `calendar`'s midnight — what a renderer or a
    /// day-bucketer wants, so an all-day item sorts and groups alongside that day's timed
    /// events instead of five hours before them.
    public static func localDay(of instant: Date, calendar: Calendar) -> Date {
        let parts = utc.dateComponents([.year, .month, .day], from: instant)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: instant)
    }

    /// The canonical anchor for the calendar date `instant` names *in `calendar`* — the inverse
    /// of `localDay(of:calendar:)`.
    ///
    /// For date-only values that were parsed at local midnight and are only now becoming
    /// all-day events: the School framework's Key Dates travel as `YYYY-MM-DD` and are read
    /// back in the local zone (`TermDay`), which is right for term arithmetic and wrong the
    /// moment one is handed to the calendar as an event.
    public static func anchor(forDayOf instant: Date, in calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return utc.date(from: parts) ?? utcDay(of: instant)
    }
}
