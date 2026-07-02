import Foundation
import UserNotifications
import AtlasCore

/// Bridges the pure `NotificationPlanner` to iOS. Requests authorization, and on
/// each snapshot/prefs change clears pending requests and re-adds the plan.
/// A tapped notification routes its `deepLink` back through the Task 1 handler.
@MainActor
final class NotificationScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    private let center = UNUserNotificationCenter.current()

    /// Set by the app to route a tapped notification's deep link into the store.
    /// Assigning it flushes any link buffered before it was wired (cold-launch tap).
    var onDeepLink: ((URL) -> Void)? {
        didSet {
            guard let handler = onDeepLink, let url = pendingURL else { return }
            pendingURL = nil
            handler(url)
        }
    }

    /// A deep link received before `onDeepLink` was wired (cold launch), held until it is.
    private var pendingURL: URL?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Replace all pending notifications with the freshly planned set.
    func reschedule(snapshot: AtlasSnapshot, prefs: NotificationPrefs,
                    now: Date = Date(), horizonDays: Int = 14) {
        let planned = NotificationPlanner.plan(
            snapshot: snapshot, prefs: NotificationPlanner.Prefs(prefs),
            now: now, horizonDays: horizonDays)

        center.removeAllPendingNotificationRequests()

        let cal = Calendar.current
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = ["deepLink": item.deepLink]

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let deepLink = response.notification.request.content.userInfo["deepLink"] as? String
        await MainActor.run {
            guard let deepLink, let url = URL(string: deepLink) else { return }
            if let onDeepLink { onDeepLink(url) } else { pendingURL = url }   // buffer until wired
        }
    }
}

extension NotificationPlanner.Prefs {
    /// Map the app-side prefs into the planner's mirror type.
    init(_ p: NotificationPrefs) {
        self.init(enabled: p.enabled, events: p.events, tasksDue: p.tasksDue,
                  digest: p.digest, overdue: p.overdue, leadMinutes: p.leadMinutes,
                  digestHour: p.digestHour, digestMinute: p.digestMinute, spaceIds: p.spaceIds)
    }
}
