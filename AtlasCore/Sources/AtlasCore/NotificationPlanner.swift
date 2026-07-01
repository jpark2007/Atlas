import Foundation

/// A single local notification the app should schedule. `id` is stable across
/// re-plans (used as the `UNNotificationRequest` identifier) so re-scheduling
/// replaces rather than duplicates.
public struct PlannedNotification: Equatable {
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let deepLink: String   // atlas://…

    public init(id: String, fireDate: Date, title: String, body: String, deepLink: String) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.deepLink = deepLink
    }
}

/// Pure planner that turns a data snapshot + user prefs into the local
/// notifications to schedule. Deterministic given `now` — no hidden clock — so it
/// is fully unit-testable. The iOS scheduler feeds the result to
/// `UNUserNotificationCenter`.
public enum NotificationPlanner {

    /// Field-for-field mirror of `AtlasMobile.NotificationPrefs` (the planner lives
    /// in AtlasCore, so it owns its own copy of the shape).
    public struct Prefs: Equatable {
        public var enabled: Bool
        public var events: Bool
        public var tasksDue: Bool
        public var digest: Bool
        public var overdue: Bool
        public var leadMinutes: Int
        public var digestHour: Int
        public var digestMinute: Int
        public var spaceIds: [UUID]?

        public init(enabled: Bool, events: Bool, tasksDue: Bool, digest: Bool, overdue: Bool,
                    leadMinutes: Int, digestHour: Int, digestMinute: Int, spaceIds: [UUID]?) {
            self.enabled = enabled
            self.events = events
            self.tasksDue = tasksDue
            self.digest = digest
            self.overdue = overdue
            self.leadMinutes = leadMinutes
            self.digestHour = digestHour
            self.digestMinute = digestMinute
            self.spaceIds = spaceIds
        }
    }

    /// iOS keeps ~64 pending local notifications; keep the soonest 60.
    private static let maxPending = 60
    /// Fixed morning hour for a due-only (all-day) task with no specific time.
    private static let dueOnlyReminderHour = 9

    public static func plan(snapshot: AtlasSnapshot, prefs: Prefs,
                            now: Date, horizonDays: Int) -> [PlannedNotification] {
        guard prefs.enabled else { return [] }

        let cal = Calendar.current
        let horizon = cal.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let lead = TimeInterval(prefs.leadMinutes * 60)

        // Resolve the space filter (nil = all) into a set of allowed space names.
        let allowedNames: Set<String>? = prefs.spaceIds.map { ids in
            Set(snapshot.spaces.filter { ids.contains($0.id) }.map(\.name))
        }
        func allowed(_ spaceName: String) -> Bool {
            guard let allowedNames else { return true }
            return allowedNames.contains(spaceName)
        }

        var planned: [PlannedNotification] = []

        // 1. Event reminders (timed events only) at start − lead.
        if prefs.events {
            for ev in snapshot.events where !ev.isAllDay && allowed(ev.spaceName) {
                guard ev.start <= horizon else { continue }
                let fire = ev.start.addingTimeInterval(-lead)
                guard fire > now else { continue }
                planned.append(PlannedNotification(
                    id: "event-\(ev.id.uuidString)",
                    fireDate: fire,
                    title: ev.title,
                    body: "Starts at \(clock(ev.start, cal: cal))",
                    deepLink: "atlas://today"))
            }
        }

        // 2. Task-due reminders.
        if prefs.tasksDue {
            for t in snapshot.tasks where !t.done && allowed(t.spaceName) {
                guard let fire = taskFireDate(t, lead: lead, cal: cal, horizon: horizon) else { continue }
                guard fire > now else { continue }
                planned.append(PlannedNotification(
                    id: "task-\(t.id.uuidString)",
                    fireDate: fire,
                    title: t.title,
                    body: "Due \(TaskItem.dueLabel(for: t.dueDate, now: now))",
                    deepLink: "atlas://today"))
            }
        }

        // 3. Daily digest — one per day across the horizon, summarizing that day.
        if prefs.digest {
            for offset in 0..<max(horizonDays, 1) {
                guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                      let fire = cal.date(bySettingHour: prefs.digestHour, minute: prefs.digestMinute,
                                          second: 0, of: day),
                      fire > now else { continue }
                let eventCount = snapshot.events.filter {
                    allowed($0.spaceName) && cal.isDate($0.start, inSameDayAs: day)
                }.count
                let taskCount = snapshot.tasks.filter { t in
                    guard !t.done, allowed(t.spaceName), let when = t.scheduledAt ?? t.dueDate else { return false }
                    return cal.isDate(when, inSameDayAs: day)
                }.count
                guard eventCount + taskCount > 0 else { continue }
                planned.append(PlannedNotification(
                    id: "digest-\(dayKey(day, cal: cal))",
                    fireDate: fire,
                    title: "Your day",
                    body: "\(pluralized(eventCount, "event")) · \(pluralized(taskCount, "task"))",
                    deepLink: "atlas://today"))
            }
        }

        // 4. Overdue nudge — one summary at the next digest time.
        if prefs.overdue {
            let overdueCount = snapshot.tasks.filter { allowed($0.spaceName) && $0.isOverdue(now: now) }.count
            if overdueCount > 0, let fire = nextDigestTime(prefs: prefs, now: now, cal: cal) {
                planned.append(PlannedNotification(
                    id: "overdue-\(dayKey(fire, cal: cal))",
                    fireDate: fire,
                    title: "Overdue",
                    body: "\(pluralized(overdueCount, "task")) overdue",
                    deepLink: "atlas://today"))
            }
        }

        // Soonest first (id tie-break for full determinism), capped.
        let sorted = planned.sorted {
            $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.id < $1.id
        }
        return Array(sorted.prefix(maxPending))
    }

    // MARK: - Helpers

    /// When a task's reminder should fire: timed → scheduledAt − lead; a due with a
    /// specific time → due − lead; a due-only (midnight) task → 9am on its due day.
    private static func taskFireDate(_ t: TaskItem, lead: TimeInterval,
                                     cal: Calendar, horizon: Date) -> Date? {
        if let scheduled = t.scheduledAt {
            guard scheduled <= horizon else { return nil }
            return scheduled.addingTimeInterval(-lead)
        }
        guard let due = t.dueDate, due <= horizon else { return nil }
        let hour = cal.component(.hour, from: due)
        let minute = cal.component(.minute, from: due)
        if hour != 0 || minute != 0 {
            return due.addingTimeInterval(-lead)
        }
        return cal.date(bySettingHour: dueOnlyReminderHour, minute: 0, second: 0,
                        of: cal.startOfDay(for: due))
    }

    private static func nextDigestTime(prefs: Prefs, now: Date, cal: Calendar) -> Date? {
        let today = cal.startOfDay(for: now)
        guard let t = cal.date(bySettingHour: prefs.digestHour, minute: prefs.digestMinute,
                               second: 0, of: today) else { return nil }
        return t > now ? t : cal.date(byAdding: .day, value: 1, to: t)
    }

    private static func clock(_ date: Date, cal: Calendar) -> String {
        let f = DateFormatter()
        f.dateFormat = cal.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return f.string(from: date)
    }

    private static func dayKey(_ date: Date, cal: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = cal.timeZone
        return f.string(from: date)
    }

    private static func pluralized(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
