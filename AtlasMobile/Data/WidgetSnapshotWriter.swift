import Foundation
import SwiftUI
import WidgetKit
import AtlasCore

/// App-side: distill the live `AtlasSnapshot` into today's `SharedSnapshot` and
/// write it to the app-group container, then nudge WidgetKit to reload. Reuses the
/// shared `AgendaBuilder` so the widget's timeline matches the Schedule screen.
enum WidgetSnapshotWriter {

    static func write(_ snapshot: AtlasSnapshot, now: Date = Date()) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)

        let sections = AgendaBuilder.build(events: snapshot.events, tasks: snapshot.tasks, from: now, now: now)
        let items = (sections.first { cal.isDate($0.day, inSameDayAs: day) }?.items ?? [])
            .filter { !($0.kind == .task && $0.allDay) }   // due-only tasks are the "needs a time" pill

        let rows = items.map { item -> SharedSnapshot.Row in
            let timed = !item.allDay
            let start = timed ? item.date.timeIntervalSince1970 : 0
            let end = timed ? (item.endDate ?? item.date.addingTimeInterval(3600)).timeIntervalSince1970 : 0
            return SharedSnapshot.Row(
                time: item.allDay ? "all-day" : clock(item.date, cal: cal),
                title: item.title,
                spaceName: item.spaceName,
                spaceColorHex: hex(item.color),
                startEpoch: start,
                endEpoch: end)
        }

        let needTime = snapshot.tasks.filter { task in
            guard let due = task.dueDate, task.scheduledAt == nil, !task.done else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }.count

        let timed = snapshot.tasks.filter { task in
            guard let at = task.scheduledAt, !task.done else { return false }
            return cal.isDate(at, inSameDayAs: day)
        }.count

        // Events still ahead today also count toward "N left" (aligns with ScheduleView's
        // leftCount): an event counts while it hasn't ended.
        let liveEvents = snapshot.events.filter { event in
            cal.isDate(event.start, inSameDayAs: day) && event.end > now
        }.count

        let spaces = snapshot.spaces.map {
            SharedSnapshot.SpaceRef(id: $0.id.uuidString, name: $0.name, colorHex: hex($0.color))
        }

        let shared = SharedSnapshot(
            today: rows,
            needTimeCount: needTime,
            leftCount: needTime + timed + liveEvents,
            dateLabel: dateLabel(now),
            spaces: spaces,
            generatedAt: now)

        shared.write()
        writeCache(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Offline snapshot cache (G1)

    /// Full-snapshot mirror for offline launch, kept next to `today.json` in the
    /// app group. Encoded via the same Codable row DTOs the DB uses, so it reuses
    /// their `init(domain:)`/`toDomain()` round-trip. Only the tables the mobile UI
    /// renders are cached (notes/goals are unused there).
    private struct SnapshotCache: Codable {
        var spaces: [SpaceRow]
        var projects: [ProjectRow]
        var tasks: [TaskRow]
        var events: [EventRow]
    }

    private static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedSnapshot.appGroup)?
            .appendingPathComponent("snapshot-cache.json")
    }

    private static func writeCache(_ snapshot: AtlasSnapshot) {
        guard let url = cacheURL else { return }
        let cache = SnapshotCache(
            spaces: snapshot.spaces.map { SpaceRow(domain: $0) },
            projects: snapshot.projects.map { ProjectRow(domain: $0) },
            tasks: snapshot.tasks.map { TaskRow(domain: $0) },
            // `CalendarEvent` carries no canvasUID and `EventRow(domain:)` hardcodes
            // canvas_uid = nil (correct for the DB-upsert path), so a cached Canvas event
            // would otherwise reload as an editable Atlas/Google event — a source mislabel
            // (CLAUDE.md rule 5) with an offline write window. Stamp a cache-local sentinel
            // instead: `toDomain()` derives `.canvas` + read-only from canvas_uid != nil, so
            // Canvas events survive the offline round-trip correctly labeled (today's classes
            // ARE the offline first frame). The sentinel never reaches the server — this file
            // is app-private, Canvas events have no write path in the UI, and any upsert
            // re-maps through EventRow(domain:) which nulls canvas_uid anyway.
            events: snapshot.events.map { e in
                var row = EventRow(domain: e)
                if e.source == .canvas { row.canvasUid = "cached-canvas" }
                return row
            })
        // Best-effort: a failed cache write just means no offline snapshot next launch.
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }

    /// Decode the last cached snapshot for an offline/first-frame launch. Row DTOs
    /// don't persist colors, so events/projects come back stamped accent — the caller
    /// (`MobileStore`) recolors from `spaceName`, exactly like a network load.
    static func loadCache() -> AtlasSnapshot? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(SnapshotCache.self, from: data)
        else { return nil }
        return AtlasSnapshot(
            spaces: cache.spaces.map { $0.toDomain() },
            projects: cache.projects.map { $0.toDomain() },
            tasks: cache.tasks.map { $0.toDomain() },
            events: cache.events.map { $0.toDomain() },
            notes: [],
            goals: [])
    }

    // MARK: - Helpers

    private static let clockHour: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h a"; return f }()
    private static let clockHourMinute: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    private static let dateLabelFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()

    private static func clock(_ date: Date, cal: Calendar) -> String {
        (cal.component(.minute, from: date) == 0 ? clockHour : clockHourMinute).string(from: date)
    }

    private static func dateLabel(_ date: Date) -> String {
        dateLabelFormatter.string(from: date)
    }

    private static func hex(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
