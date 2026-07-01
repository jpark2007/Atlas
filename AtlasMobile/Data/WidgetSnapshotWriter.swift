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

        let rows = items.map { item in
            SharedSnapshot.Row(
                time: item.allDay ? "all-day" : clock(item.date, cal: cal),
                title: item.title,
                spaceName: item.spaceName,
                spaceColorHex: hex(item.color),
                isNow: isNow(item, now: now, cal: cal))
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

    private static func isNow(_ item: AgendaItem, now: Date, cal: Calendar) -> Bool {
        guard cal.isDateInToday(item.date), !item.allDay else { return false }
        let end = item.endDate ?? item.date.addingTimeInterval(3600)
        return item.date <= now && now < end
    }

    private static func clock(_ date: Date, cal: Calendar) -> String {
        let f = DateFormatter()
        f.dateFormat = cal.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return f.string(from: date)
    }

    private static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private static func hex(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
