import Foundation

/// A downloaded `.ics` FILE — the "Export course schedule" button most registrars have,
/// which hands the student a file rather than a subscribable link.
///
/// A link is a feed: the server re-syncs it forever (`feeds-sync`). A file has no
/// address to go back to, so it is read once, here on the client, and turned into
/// classes with their meeting times. That is the same landing place the link door
/// reaches — the class knows its meeting blocks and `SchoolCalendar` draws them — with
/// no feed row and nothing to re-sync.
///
/// Deliberately partial: only what a class schedule needs — SUMMARY, DTSTART/DTEND,
/// LOCATION, and a weekly RRULE. Everything else in the file is ignored rather than
/// half-understood.
public enum ICSFile {

    /// One VEVENT, reduced to the five things a class schedule carries.
    public struct Event: Equatable {
        public let summary: String
        public let start: Date
        public let end: Date?
        public let location: String?
        /// Weekdays a WEEKLY RRULE repeats on, in `Calendar` numbering (1 = Sunday).
        /// Empty when the event carries no weekly rule — it happens once.
        public let weekdays: [Int]
    }

    /// A class found in the file, with the meeting blocks its events describe.
    public struct Course: Equatable, Identifiable {
        public var id: String { code ?? name }
        public let name: String
        public let code: String?
        public let meetings: [MeetingBlock]
    }

    // MARK: - Courses

    /// The classes `raw` describes. Events are attributed exactly the way the server
    /// attributes feed items (`_shared/ics.ts`): a trailing `[CODE]` is the course, and
    /// what's left is the title. Occurrences of the same class at the same time are
    /// folded into one meeting block whose weekdays are the union of theirs, so a file
    /// that spells out fifteen Mondays and fifteen Wednesdays lands as "MW".
    public static func courses(in raw: String, calendar: Calendar = .current) -> [Course] {
        var order: [String] = []
        var grouped: [String: [(title: String, code: String?, event: Event)]] = [:]

        for event in events(in: raw, calendar: calendar) {
            let parsed = course(from: event.summary)
            guard !parsed.title.isEmpty || parsed.code != nil else { continue }
            let key = parsed.code.map(normalizeCode) ?? parsed.title.lowercased()
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append((parsed.title, parsed.code, event))
        }

        return order.compactMap { key -> Course? in
            guard let entries = grouped[key] else { return nil }
            let name = entries.first(where: { !$0.title.isEmpty })?.title
                ?? entries.first?.code
                ?? ""
            guard !name.isEmpty else { return nil }
            return Course(name: name,
                          code: entries.compactMap(\.code).first,
                          meetings: meetingBlocks(from: entries.map(\.event), calendar: calendar))
        }
    }

    /// `"Organic Chemistry [CHEM 201]"` → `("Organic Chemistry", "CHEM 201")`.
    /// No bracket ⇒ the whole summary is the title and there is no code.
    public static func course(from summary: String) -> (title: String, code: String?) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("]"), let open = trimmed.lastIndex(of: "[") else {
            return (trimmed, nil)
        }
        let code = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        let title = String(trimmed[trimmed.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        return (title, code.isEmpty ? nil : code)
    }

    /// Whitespace-stripped, uppercased — how the server compares course codes.
    public static func normalizeCode(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).joined().uppercased()
    }

    /// Folds occurrences into blocks: one per distinct start/end/location, carrying every
    /// weekday it was seen on. An event with no end time has no duration to draw, so it
    /// is dropped rather than guessed at.
    private static func meetingBlocks(from events: [Event], calendar: Calendar) -> [MeetingBlock] {
        var order: [String] = []
        var days: [String: Set<Int>] = [:]
        var shape: [String: (start: String, end: String, location: String?)] = [:]

        for event in events {
            guard let end = event.end else { continue }
            let startHHMM = clock(event.start, calendar), endHHMM = clock(end, calendar)
            guard startHHMM != endHHMM else { continue }
            let key = "\(startHHMM)|\(endHHMM)|\(event.location ?? "")"
            if days[key] == nil {
                order.append(key)
                shape[key] = (startHHMM, endHHMM, event.location)
            }
            let weekdays = event.weekdays.isEmpty
                ? [calendar.component(.weekday, from: event.start)]
                : event.weekdays
            days[key, default: []].formUnion(weekdays)
        }

        return order.compactMap { key in
            guard let s = shape[key], let d = days[key] else { return nil }
            return MeetingBlock(weekdays: d.sorted(), start: s.start, end: s.end, location: s.location)
        }
        .sorted { $0.start < $1.start }
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: - Events

    /// Every VEVENT in `raw` that has a summary and a start.
    public static func events(in raw: String, calendar: Calendar = .current) -> [Event] {
        var result: [Event] = []
        var inEvent = false
        var summary: String?, location: String?, rrule: String?
        var start: Date?, end: Date?

        for line in unfold(raw) {
            guard let prop = property(line) else { continue }
            switch prop.name {
            case "BEGIN" where prop.value == "VEVENT":
                inEvent = true
                summary = nil; location = nil; rrule = nil; start = nil; end = nil
            case "END" where prop.value == "VEVENT":
                if inEvent, let summary, let start, !summary.isEmpty {
                    result.append(Event(summary: summary, start: start, end: end, location: location,
                                        weekdays: weeklyDays(rrule)))
                }
                inEvent = false
            case "SUMMARY"  where inEvent: summary = unescape(prop.value)
            case "LOCATION" where inEvent: location = unescape(prop.value).isEmpty ? nil : unescape(prop.value)
            case "RRULE"    where inEvent: rrule = prop.value
            case "DTSTART"  where inEvent: start = date(prop, calendar: calendar)
            case "DTEND"    where inEvent: end = date(prop, calendar: calendar)
            default: break
            }
        }
        return result
    }

    /// The weekdays of a `FREQ=WEEKLY` rule, in `Calendar` numbering. Any other frequency
    /// (or a weekly rule with no BYDAY) yields none — the event's own day is used instead.
    private static func weeklyDays(_ rrule: String?) -> [Int] {
        guard let rrule else { return [] }
        var parts: [String: String] = [:]
        for pair in rrule.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[kv[0].uppercased()] = String(kv[1]) }
        }
        guard parts["FREQ"]?.uppercased() == "WEEKLY", let byDay = parts["BYDAY"] else { return [] }
        let numbers = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        return byDay.split(separator: ",").compactMap { token in
            // BYDAY entries may be ordinal-prefixed ("2MO"); the day is the last two chars.
            numbers[String(token.suffix(2)).uppercased()]
        }.sorted()
    }

    // MARK: - Lines

    private struct Property { let name: String; let params: [String: String]; let value: String }

    /// RFC 5545 line unfolding: a line beginning with a space or tab continues the one
    /// before it.
    private static func unfold(_ raw: String) -> [String] {
        var lines: [String] = []
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    /// `NAME;PARAM=VALUE:the value` — the split is on the first colon outside quotes.
    private static func property(_ line: String) -> Property? {
        var quoted = false
        var colon: String.Index?
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" { quoted.toggle() } else if c == ":" && !quoted { colon = i; break }
            i = line.index(after: i)
        }
        guard let colon else { return nil }
        let head = line[line.startIndex..<colon].split(separator: ";")
        guard let name = head.first else { return nil }

        var params: [String: String] = [:]
        for param in head.dropFirst() {
            let kv = param.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[kv[0].uppercased()] = String(kv[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return Property(name: name.uppercased(), params: params,
                        value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func unescape(_ v: String) -> String {
        v.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `20260901T100000` / `…Z` / `VALUE=DATE`. A floating time (no Z, no TZID) is read
    /// as local wall time — which is what a timetable means by "10:00".
    private static func date(_ prop: Property, calendar: Calendar) -> Date? {
        let value = prop.value
        let zone: TimeZone = value.hasSuffix("Z")
            ? TimeZone(identifier: "UTC")!
            : prop.params["TZID"].flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = prop.params["VALUE"] == "DATE" ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss"
        return formatter.date(from: value.hasSuffix("Z") ? String(value.dropLast()) : value)
    }
}
