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

        let spaces = snapshot.spaces.map {
            SharedSnapshot.SpaceRef(id: $0.id.uuidString, name: $0.name, colorHex: hex($0.color))
        }

        let shared = SharedSnapshot(
            today: rows,
            needTimeCount: needTime,
            leftCount: needTime + timed,
            dateLabel: dateLabel(now),
            spaces: spaces,
            generatedAt: now)

        shared.write()
        WidgetCenter.shared.reloadAllTimelines()
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
