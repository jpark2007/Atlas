import Foundation

/// Platform-neutral pure core for cross-device settings sync (`user_settings`,
/// migration 0025), shared by the Mac and iOS `SettingsSyncService`s. Each platform
/// keeps its own key map / apply / read-local for the columns it actually consumes;
/// these two functions — the row overlay and the redundant-push guard — are identical
/// on both sides, so they live here and are unit-tested once (AtlasCore has the only
/// shared test target).
public enum UserSettingsMerge {

    /// The row to push: start from `base` (the last-pulled row, so columns THIS device
    /// has no local source for survive), overlay each non-nil field of `local`, and
    /// stamp `userId`. `updatedAt` is always dropped — the server owns it.
    ///
    /// A device expresses its local values as a `UserSettingsRow` whose owned columns
    /// are set and whose non-owned columns are left nil; nil ⇒ "keep the base value".
    public static func overlay(base: UserSettingsRow?, local: UserSettingsRow, userId: UUID) -> UserSettingsRow {
        UserSettingsRow(
            userId: userId,
            defaultSpaceName:          local.defaultSpaceName          ?? base?.defaultSpaceName,
            appleCalendarDefaultSpace: local.appleCalendarDefaultSpace ?? base?.appleCalendarDefaultSpace,
            textScale:                 local.textScale                 ?? base?.textScale,
            sidebarMode:               local.sidebarMode               ?? base?.sidebarMode,
            tasksGrouping:             local.tasksGrouping             ?? base?.tasksGrouping,
            perTabDocsSync:            local.perTabDocsSync            ?? base?.perTabDocsSync,
            notificationPrefsJSON:     local.notificationPrefsJSON     ?? base?.notificationPrefsJSON,
            updatedAt:                 nil   // server stamps updated_at; never sent from the client
        )
    }

    /// True when `row` carries nothing the last-pulled row doesn't already have — the
    /// case after a pull writes server values into local storage and the resulting
    /// change echoes schedule a (non-user-initiated) push. Value-based, so it's immune
    /// to the async gap between the defaults write and the `.onChange` tick; the
    /// server-stamped `updatedAt` is ignored on both sides.
    public static func isRedundantPush(_ row: UserSettingsRow, lastPulled: UserSettingsRow?) -> Bool {
        guard var baseline = lastPulled else { return false }
        baseline.updatedAt = nil
        var candidate = row
        candidate.updatedAt = nil
        return candidate == baseline
    }
}
