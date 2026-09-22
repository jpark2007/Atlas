import Foundation

/// A tiny in-memory ring buffer of the app's most recent diagnostic lines, so a
/// bug report can carry the tail of what just happened. Not persisted, never sent
/// anywhere on its own — the "Report a bug" sheet reads `snapshot()` and attaches
/// it only when the user files a report. Keeps the last `capacity` lines, each
/// stamped with an ISO-8601 UTC time.
///
/// Thread-safe via a private lock; `append` is cheap and callable from anywhere
/// (sync/async, any actor). Wire it at high-value failure points (catch blocks).
public enum AtlasLog {
    private static let capacity = 200
    private static let lock = NSLock()
    private static var lines: [String] = []

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Record one diagnostic line. Oldest lines drop off once past `capacity`.
    public static func append(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)"
        lock.lock()
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        lock.unlock()
    }

    /// The buffered lines joined newest-last, ready to attach to a bug report.
    /// Empty string when nothing has been logged yet.
    public static func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    /// What a bug report attaches as its `log`: one context line (time zone, locale, OS),
    /// then the newest buffered lines, within the column's 16,000-character limit. Never
    /// empty — the buffer only records failures, so a clean session used to send no log at
    /// all, and a date bug's report then left the reporter's time zone to guesswork.
    public static func reportAttachment(timeZone: TimeZone = .current) -> String {
        let context = "context: tz=\(timeZone.identifier) locale=\(Locale.current.identifier) "
            + "os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
        let tail = snapshot()
        guard !tail.isEmpty else { return context }
        return context + "\n" + String(tail.suffix(max(0, 16000 - context.count - 1)))
    }
}
