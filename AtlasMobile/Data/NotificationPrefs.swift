import Foundation

/// User notification preferences (spec §7). Persisted as JSON via `@AppStorage`
/// (RawRepresentable below) under the key `notificationPrefs`. Task 8's
/// `NotificationScheduler` reads the same key and maps this into
/// `NotificationPlanner.Prefs` field-for-field.
struct NotificationPrefs: Equatable {
    var enabled: Bool          // master
    var events: Bool
    var tasksDue: Bool
    var digest: Bool
    var overdue: Bool
    var leadMinutes: Int       // 0, 5, 15, 30, 60
    var digestHour: Int
    var digestMinute: Int
    var spaceIds: [UUID]?      // nil = all spaces

    static let `default` = NotificationPrefs(
        enabled: true,
        events: true,
        tasksDue: true,
        digest: true,
        overdue: true,
        leadMinutes: 15,
        digestHour: 8,
        digestMinute: 0,
        spaceIds: nil
    )
}

// Allow `@AppStorage("notificationPrefs") var prefs = NotificationPrefs.default`.
// NOTE: the type itself must NOT be Codable — combined with RawRepresentable,
// Swift's stdlib `RawRepresentable.encode(to:)` witness makes `rawValue` ↔
// `JSONEncoder.encode(self)` mutually recursive (stack-overflow crash at
// launch). JSON goes through the private `Stored` mirror instead.
extension NotificationPrefs: RawRepresentable {
    private struct Stored: Codable {
        var enabled: Bool
        var events: Bool
        var tasksDue: Bool
        var digest: Bool
        var overdue: Bool
        var leadMinutes: Int
        var digestHour: Int
        var digestMinute: Int
        var spaceIds: [UUID]?
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        self = NotificationPrefs(
            enabled: s.enabled, events: s.events, tasksDue: s.tasksDue,
            digest: s.digest, overdue: s.overdue, leadMinutes: s.leadMinutes,
            digestHour: s.digestHour, digestMinute: s.digestMinute, spaceIds: s.spaceIds)
    }

    var rawValue: String {
        let s = Stored(
            enabled: enabled, events: events, tasksDue: tasksDue,
            digest: digest, overdue: overdue, leadMinutes: leadMinutes,
            digestHour: digestHour, digestMinute: digestMinute, spaceIds: spaceIds)
        guard let data = try? JSONEncoder().encode(s),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
