import Foundation

/// Parses ISO-8601 date strings returned by the `capture` edge function,
/// tolerating both fractional and whole-second formats. Shared by task and
/// event capture so the two paths never drift.
public enum CaptureDateParser {
    public static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        // Model sometimes returns date-only: "2026-06-30"
        f.formatOptions = [.withFullDate]
        return f.date(from: iso)
    }
}
