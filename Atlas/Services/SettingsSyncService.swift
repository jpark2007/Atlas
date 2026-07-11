import Foundation
import AtlasCore

/// Syncs the handful of user preferences that should follow the account across
/// devices (Mac ↔ phone) through the `user_settings` row (migration 0025).
///
/// Merge policy (mirrors the phone side):
///   • **Pull** at bootstrap and on app-foreground — the SERVER wins: each non-nil
///     column is written straight to its local `@AppStorage`/UserDefaults key.
///   • **Push** ONLY on a user-initiated change of a synced setting (never at
///     launch, so a fresh device's defaults can't clobber the server). The pushed
///     row starts from the last-pulled row and overlays the present local values,
///     so phone-owned columns Atlas-for-Mac has no UI for (`tasks_grouping`,
///     `notification_prefs`) are never nulled out. A push whose row matches the
///     last-pulled row is skipped — pull-applied values echo through the synced
///     keys' `.onChange` handlers, and those echoes must not upsert.
///
/// Best-effort throughout: the `user_settings` table deploys in a later gated
/// migration, so `loadUserSettings()` / `upsertUserSettings()` can fail today.
/// Every failure is swallowed — a settings sync is never worth surfacing an error.
@MainActor
final class SettingsSyncService: ObservableObject {

    /// The UserDefaults the synced keys live in (the same store `@AppStorage` uses).
    private static let syncedDefaults = UserDefaults.standard

    /// The last row seen from the server (pulled, or written by our own push). A
    /// push overlays local values onto THIS so phone-owned columns survive.
    private var lastPulledRow: UserSettingsRow?

    /// In-flight debounce for push — cancelled and replaced on every change so a
    /// settings-screen drag collapses into a single upsert.
    private var pushTask: Task<Void, Never>?

    // MARK: - Local UserDefaults keys ↔ columns

    enum Key {
        static let defaultSpaceName          = "tasks.defaultSpaceName"          // default_space_name
        static let appleCalendarDefaultSpace = "calendar.apple.defaultSpace"     // apple_calendar_default_space
        static let googleTwoWaySync          = "calendar.google.enabled"         // google_two_way_sync
        static let textScale                 = "appearance.textScale"            // text_scale
        static let sidebarMode               = "sidebar.mode"                    // sidebar_mode
        static let perTabDocsSync            = "notes.perTabDocsSync.enabled"    // per_tab_docs_sync
        // Phone-owned but applied locally on pull BY DESIGN — the later Mac
        // notifications task consumes this UserDefaults key.
        static let notificationPrefs         = "notificationPrefs"               // notification_prefs
        // `tasks_grouping` has NO local mapping (no Mac consumer): never applied,
        // never read; it survives Mac pushes via `mergedRow`'s base overlay.
    }

    // MARK: - Pull (server wins)

    /// Loads the server row and applies each non-nil column to UserDefaults.
    /// Silently no-ops on any error (table not yet deployed) or when no row exists.
    func pullAndApply(db: AtlasDB) async {
        // `try?` flattens the throwing Optional: nil ⇒ error (table absent) OR no row.
        guard let row = try? await db.loadUserSettings() else { return }
        lastPulledRow = row
        for write in Self.applies(from: row) {
            write.apply(to: Self.syncedDefaults)
        }
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
        let local = Self.readLocal(from: Self.syncedDefaults)
        let row = Self.mergedRow(base: lastPulledRow, local: local, userId: userId)
        // A pull writes server values into UserDefaults, which fires the synced
        // keys' `.onChange` handlers and schedules a push that isn't user-initiated.
        // Skip when the row carries nothing new (also swallows `.onAppear` heals
        // that re-write the already-synced value).
        guard !Self.isRedundantPush(row, lastPulled: lastPulledRow) else { return }
        do {
            try await db.upsertUserSettings(row)
            lastPulledRow = row   // keep the cache coherent with what we just wrote
        } catch {
            print("[SettingsSync] push failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pure logic (unit-tested)

    /// The current local values, `nil` for any key that is ABSENT — so a push
    /// leaves the server/phone value untouched rather than overwriting with a
    /// device default (`bool(forKey:)`/`double(forKey:)` can't tell absent from 0).
    struct LocalSnapshot: Equatable {
        var defaultSpaceName: String? = nil
        var appleCalendarDefaultSpace: String? = nil
        var googleTwoWaySync: Bool? = nil
        var textScale: Double? = nil
        var sidebarMode: String? = nil
        var perTabDocsSync: Bool? = nil
        var notificationPrefsJSON: String? = nil
    }

    /// A single typed UserDefaults write, so the pull's key/value mapping is a pure,
    /// testable value before it touches the store.
    enum DefaultsValue: Equatable {
        case string(String)
        case bool(Bool)
        case double(Double)
    }

    struct DefaultsWrite: Equatable {
        let key: String
        let value: DefaultsValue
        func apply(to defaults: UserDefaults) {
            switch value {
            case .string(let s): defaults.set(s, forKey: key)
            case .bool(let b):   defaults.set(b, forKey: key)
            case .double(let d): defaults.set(d, forKey: key)
            }
        }
    }

    /// Server-wins pull: one write per non-nil column, mapped to its local key/type.
    nonisolated static func applies(from row: UserSettingsRow) -> [DefaultsWrite] {
        var writes: [DefaultsWrite] = []
        if let v = row.defaultSpaceName          { writes.append(.init(key: Key.defaultSpaceName,          value: .string(v))) }
        if let v = row.appleCalendarDefaultSpace { writes.append(.init(key: Key.appleCalendarDefaultSpace, value: .string(v))) }
        if let v = row.googleTwoWaySync          { writes.append(.init(key: Key.googleTwoWaySync,          value: .bool(v)))   }
        if let v = row.textScale                 { writes.append(.init(key: Key.textScale,                 value: .double(v))) }
        if let v = row.sidebarMode               { writes.append(.init(key: Key.sidebarMode,               value: .string(v))) }
        if let v = row.perTabDocsSync            { writes.append(.init(key: Key.perTabDocsSync,            value: .bool(v)))   }
        if let v = row.notificationPrefsJSON     { writes.append(.init(key: Key.notificationPrefs,         value: .string(v))) }
        return writes
    }

    /// Reads the current local values from a UserDefaults, treating an absent key
    /// as `nil` (present-with-value stays present, including `false`/`0`/`""`).
    nonisolated static func readLocal(from defaults: UserDefaults) -> LocalSnapshot {
        LocalSnapshot(
            defaultSpaceName:          defaults.string(forKey: Key.defaultSpaceName),
            appleCalendarDefaultSpace: defaults.string(forKey: Key.appleCalendarDefaultSpace),
            googleTwoWaySync:          defaults.object(forKey: Key.googleTwoWaySync) == nil ? nil : defaults.bool(forKey: Key.googleTwoWaySync),
            textScale:                 defaults.object(forKey: Key.textScale) == nil ? nil : defaults.double(forKey: Key.textScale),
            sidebarMode:               defaults.string(forKey: Key.sidebarMode),
            perTabDocsSync:            defaults.object(forKey: Key.perTabDocsSync) == nil ? nil : defaults.bool(forKey: Key.perTabDocsSync),
            notificationPrefsJSON:     defaults.string(forKey: Key.notificationPrefs)
        )
    }

    /// The row to push: start from `base` (last-pulled — preserves phone-owned
    /// columns), overlay each present local value, stamp the user id.
    nonisolated static func mergedRow(base: UserSettingsRow?, local: LocalSnapshot, userId: UUID) -> UserSettingsRow {
        UserSettingsRow(
            userId: userId,
            defaultSpaceName:          local.defaultSpaceName          ?? base?.defaultSpaceName,
            appleCalendarDefaultSpace: local.appleCalendarDefaultSpace ?? base?.appleCalendarDefaultSpace,
            googleTwoWaySync:          local.googleTwoWaySync          ?? base?.googleTwoWaySync,
            textScale:                 local.textScale                 ?? base?.textScale,
            sidebarMode:               local.sidebarMode               ?? base?.sidebarMode,
            tasksGrouping:             base?.tasksGrouping,   // phone-owned; no local source
            perTabDocsSync:            local.perTabDocsSync            ?? base?.perTabDocsSync,
            notificationPrefsJSON:     local.notificationPrefsJSON     ?? base?.notificationPrefsJSON,
            updatedAt:                 nil   // server stamps updated_at; never sent from the client
        )
    }

    /// True when `row` carries nothing the server doesn't already have — the case
    /// after a pull writes server values into UserDefaults and the `@AppStorage`
    /// `.onChange` handlers schedule a (non-user-initiated) push. Value-based, so
    /// it's immune to the async gap between the defaults write and the onChange
    /// tick; `updated_at` (server-stamped, never pushed) is ignored.
    nonisolated static func isRedundantPush(_ row: UserSettingsRow, lastPulled: UserSettingsRow?) -> Bool {
        guard var baseline = lastPulled else { return false }
        baseline.updatedAt = nil
        return row == baseline
    }
}
