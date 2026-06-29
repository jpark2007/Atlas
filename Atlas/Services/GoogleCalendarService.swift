import Foundation
import SwiftUI

// MARK: - Pure mapping (testable, no network)

/// Value transforms between Google Calendar's `events` JSON and Atlas
/// `CalendarEvent`s. Kept pure so the date/JSON mapping can be unit-tested
/// without hitting the network.
enum GoogleCalendarMapper {

    /// RFC 3339 (a.k.a. ISO 8601 internet date-time) for `start.dateTime` etc.
    static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `yyyy-MM-dd` (UTC) for all-day `start.date` / `end.date`.
    static let allDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: Decodable shapes

    struct EventList: Decodable { let items: [GEvent]? }

    struct GEvent: Decodable {
        let id: String?
        let summary: String?
        let description: String?
        let start: GTime?
        let end: GTime?
        /// Present on an expanded instance of a recurring series (singleEvents=true).
        let recurringEventId: String?
        /// Present on a series master if ever fetched un-expanded.
        let recurrence: [String]?
    }

    struct GTime: Decodable {
        let dateTime: String?
        let date: String?
        let timeZone: String?
    }

    // MARK: Decode → CalendarEvent

    /// Decodes a `calendars/{id}/events` list response into `CalendarEvent`s,
    /// tagged `isReadOnly: true` for the aggregate view (write-back goes through
    /// `GoogleCalendarService.create/update`, not by mutating these).
    static func decodeEvents(from data: Data,
                             defaultSpaceName: String,
                             color: Color) throws -> [CalendarEvent] {
        let list = try JSONDecoder().decode(EventList.self, from: data)
        return (list.items ?? []).compactMap { event in
            guard let (start, end, isAllDay) = interval(event.start, event.end) else { return nil }
            // A recurring instance stays read-only until series editing lands (Phase 3);
            // a one-off Google event is editable two-way (isReadOnly = false).
            let isRecurring = event.recurringEventId != nil
                || (event.recurrence?.isEmpty == false)
            return CalendarEvent(
                id: stableUUID(from: event.id ?? UUID().uuidString),
                title: event.summary ?? "Untitled",
                subtitle: "Google Calendar",
                start: start,
                end: end,
                color: color,
                spaceName: defaultSpaceName,
                notes: event.description,
                isAllDay: isAllDay,
                isReadOnly: isRecurring,
                source: .google,
                googleEventId: event.id,
                isRecurring: isRecurring
            )
        }
    }

    /// Resolves a (start, end, isAllDay) triple from a Google start/end pair.
    /// Returns nil when neither a `dateTime` nor a `date` pair parses.
    static func interval(_ start: GTime?, _ end: GTime?) -> (Date, Date, Bool)? {
        guard let start, let end else { return nil }
        if let startISO = start.dateTime, let endISO = end.dateTime,
           let startDate = rfc3339.date(from: startISO),
           let endDate = rfc3339.date(from: endISO) {
            return (startDate, endDate, false)
        }
        if let startDay = start.date, let endDay = end.date,
           let startDate = allDayFormatter.date(from: startDay),
           let endDate = allDayFormatter.date(from: endDay) {
            return (startDate, endDate, true)
        }
        return nil
    }

    // MARK: CalendarEvent → write body

    /// JSON body for `events.insert` / `events.patch` (the write-back payload).
    static func eventBody(for event: CalendarEvent) -> Data {
        var body: [String: Any] = ["summary": event.title]
        if let notes = event.notes, !notes.isEmpty { body["description"] = notes }
        if event.isAllDay {
            body["start"] = ["date": allDayFormatter.string(from: event.start)]
            body["end"] = ["date": allDayFormatter.string(from: event.end)]
        } else {
            body["start"] = ["dateTime": rfc3339.string(from: event.start)]
            body["end"] = ["dateTime": rfc3339.string(from: event.end)]
        }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// Deterministic UUID from a Google event id (FNV-1a) so re-fetches don't
    /// flicker. Mirrors `EventKitService.stableUUID`.
    static func stableUUID(from identifier: String) -> UUID {
        var h: UInt64 = 14695981039346656037
        for byte in identifier.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        let h2 = h.byteSwapped
        return UUID(uuid: (
            UInt8((h >> 56) & 0xFF), UInt8((h >> 48) & 0xFF),
            UInt8((h >> 40) & 0xFF), UInt8((h >> 32) & 0xFF),
            UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF),
            UInt8((h >>  8) & 0xFF), UInt8( h         & 0xFF),
            UInt8((h2 >> 56) & 0xFF), UInt8((h2 >> 48) & 0xFF),
            UInt8((h2 >> 40) & 0xFF), UInt8((h2 >> 32) & 0xFF),
            UInt8((h2 >> 24) & 0xFF), UInt8((h2 >> 16) & 0xFF),
            UInt8((h2 >>  8) & 0xFF), UInt8( h2         & 0xFF)
        ))
    }
}

// MARK: - Errors

enum GoogleCalendarError: LocalizedError {
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let body):
            return "Google Calendar request failed (HTTP \(code)): \(body)"
        }
    }
}

// MARK: - Service

/// Read + write-back against the user's primary Google Calendar. Reads merge into
/// `AppState.externalEvents` the same way `EventKitService` feeds Apple events;
/// writes create/update events via the `calendar.events` scope. All calls obtain
/// a fresh access token from `GoogleAuthService` and no-op (throw `.notConnected`)
/// until the user has authorized.
final class GoogleCalendarService {

    private let auth: GoogleAuthService
    private let urlSession: URLSession
    private let calendarID = "primary"
    private let apiBase = "https://www.googleapis.com/calendar/v3"

    init(auth: GoogleAuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    // MARK: Read

    /// Lists events in `[start, end)` mapped to `CalendarEvent`s for the aggregate
    /// calendar view.
    func listEvents(start: Date,
                    end: Date,
                    defaultSpaceName: String,
                    color: Color = AtlasTheme.Colors.school) async throws -> [CalendarEvent] {
        let token = try await auth.validAccessToken()

        var components = URLComponents(string: "\(apiBase)/calendars/\(calendarID)/events")!
        components.queryItems = [
            .init(name: "timeMin", value: GoogleCalendarMapper.rfc3339.string(from: start)),
            .init(name: "timeMax", value: GoogleCalendarMapper.rfc3339.string(from: end)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "250"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
        return try GoogleCalendarMapper.decodeEvents(from: data,
                                                     defaultSpaceName: defaultSpaceName,
                                                     color: color)
    }

    // MARK: Write-back

    /// Creates an event on the primary calendar. Returns the new Google event id.
    @discardableResult
    func createEvent(_ event: CalendarEvent) async throws -> String {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(apiBase)/calendars/\(calendarID)/events")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleCalendarMapper.eventBody(for: event)

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
        let created = try JSONDecoder().decode(GoogleCalendarMapper.GEvent.self, from: data)
        return created.id ?? ""
    }

    /// Updates (PATCH) an existing Google event by id.
    func updateEvent(googleEventID: String, _ event: CalendarEvent) async throws {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(apiBase)/calendars/\(calendarID)/events/\(googleEventID)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleCalendarMapper.eventBody(for: event)

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
    }

    /// Deletes a Google event by id. Treats 404/410 (already gone) as success so a
    /// local delete never gets stuck retrying a vanished event.
    func deleteEvent(googleEventID: String) async throws {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(apiBase)/calendars/\(calendarID)/events/\(googleEventID)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 || code == 410 { return }
        try Self.checkOK(response, data)
    }

    // MARK: Helper

    private static func checkOK(_ response: URLResponse, _ data: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GoogleCalendarError.requestFailed(code, String(data: data, encoding: .utf8) ?? "(no body)")
        }
    }
}
