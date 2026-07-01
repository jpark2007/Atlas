import Foundation

/// User notification preferences (spec §7). Persisted as JSON via `@AppStorage`
/// (RawRepresentable below) under the key `notificationPrefs`. Task 8's
/// `NotificationScheduler` reads the same key and maps this into
/// `NotificationPlanner.Prefs` field-for-field.
struct NotificationPrefs: Codable, Equatable {
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
extension NotificationPrefs: RawRepresentable {
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(NotificationPrefs.self, from: data) else { return nil }
        self = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
