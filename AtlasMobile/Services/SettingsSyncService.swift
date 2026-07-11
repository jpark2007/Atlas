import Foundation
import AtlasCore

/// iOS twin of the Mac `SettingsSyncService`: syncs the three preferences the phone
/// owns/consumes — the capture default space, the Tasks grouping, and notification
/// prefs — through the `user_settings` row (migration 0025), mirroring the Mac merge
/// policy verbatim. The platform-neutral overlay + redundant-push guard live in
/// `AtlasCore.UserSettingsMerge`; this type holds only the iOS key map and wiring.
///
/// Merge policy:
///   • **Pull** (bootstrap + foreground) is server-wins — each synced column is
///     written straight to its `@AppStorage` key.
///   • **Push** is debounced (500 ms, cancel-previous) and fires ONLY on a
///     user-initiated change. It overlays the present local values onto the
///     last-pulled row, so the Mac-owned columns the phone has no UI for
///     (`apple_calendar_default_space`, `google_two_way_sync`, `text_scale`,
///     `sidebar_mode`, `per_tab_docs_sync`) are never nulled. A row matching the
///     last pull is skipped — a pull's writes echo through the synced keys'
///     `.onChange` handlers, and those echoes must not upsert.
///
/// Best-effort throughout: the `user_settings` table deploys in a later gated
/// migration, so `loadUserSettings()` / `upsertUserSettings()` can fail today. Every
/// failure is swallowed — a settings sync is never worth surfacing an error.
@MainActor
final class SettingsSyncService {

    /// The UserDefaults the synced keys live in (the same store `@AppStorage` uses).
    private static let syncedDefaults = UserDefaults.standard

    /// The last row seen from the server (pulled, or written by our own push). A push
    /// overlays local values onto THIS so Mac-owned columns survive.
    private var lastPulledRow: UserSettingsRow?

    /// In-flight debounce for push — cancelled and replaced on every change so a burst
    /// of settings changes collapses into a single upsert.
    private var pushTask: Task<Void, Never>?

    /// UserDefaults keys ↔ synced columns (the three the phone owns/consumes).
    private enum Key {
        static let defaultSpaceName  = "defaultSpaceName"    // default_space_name
        static let tasksGrouping     = "tasksGrouping"       // tasks_grouping
        static let notificationPrefs = "notificationPrefs"   // notification_prefs (opaque JSON string)
    }

    // MARK: - Pull (server wins)

    /// Loads the server row and applies each non-nil synced column to UserDefaults.
    /// Silently no-ops on any error (table not yet deployed) or when no row exists.
    func pullAndApply(db: AtlasDB) async {
        // `try?` flattens the throwing Optional: nil ⇒ error (table absent) OR no row.
        guard let row = try? await db.loadUserSettings() else { return }
        lastPulledRow = row
        let d = Self.syncedDefaults
        if let v = row.defaultSpaceName      { d.set(v, forKey: Key.defaultSpaceName) }
        if let v = row.tasksGrouping         { d.set(v, forKey: Key.tasksGrouping) }
        if let v = row.notificationPrefsJSON { d.set(v, forKey: Key.notificationPrefs) }
    }

    // MARK: - Push (user-initiated, debounced)

    /// Debounced (500 ms, cancel-previous) push of the current local values.
    /// MUST be called only from a user-initiated settings change — never at launch.
    func push(db: AtlasDB) async {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.performPush(db: db)
        }
    }

    private func performPush(db: AtlasDB) async {
        guard let userId = try? await db.currentUserId() else { return }
        let d = Self.syncedDefaults
        // Local overlay row: the three phone-owned columns from UserDefaults (an absent
        // key ⇒ nil ⇒ keep the last-pulled value); Mac-owned columns stay nil so the
        // shared `overlay` preserves them from the base.
        let local = UserSettingsRow(
            userId: userId,
            defaultSpaceName:      d.string(forKey: Key.defaultSpaceName),
            tasksGrouping:         d.string(forKey: Key.tasksGrouping),
            notificationPrefsJSON: d.string(forKey: Key.notificationPrefs))
        let row = UserSettingsMerge.overlay(base: lastPulledRow, local: local, userId: userId)
        // A pull writes server values into UserDefaults, which fires the synced keys'
        // `.onChange` handlers and schedules a push that isn't user-initiated. Skip
        // when the row carries nothing new.
        guard !UserSettingsMerge.isRedundantPush(row, lastPulled: lastPulledRow) else { return }
        do {
            try await db.upsertUserSettings(row)
            lastPulledRow = row   // keep the cache coherent with what we just wrote
        } catch {
            print("[SettingsSync] push failed: \(error.localizedDescription)")
        }
    }
}
