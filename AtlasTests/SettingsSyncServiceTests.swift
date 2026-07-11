import XCTest
@testable import AtlasCore
@testable import Atlas

/// Pure-logic tests for the Mac settings-sync merge/overlay/apply core.
/// The SwiftUI wiring (bootstrap pull, foreground pull, onChange push) is
/// build-verified only.
final class SettingsSyncServiceTests: XCTestCase {

    private let uid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// A throwaway UserDefaults suite, wiped clean, so presence/absence is exact.
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "SettingsSyncServiceTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - applies(from:) — server-wins pull mapping

    func testAppliesEmitsOneTypedWritePerNonNilColumn() {
        let row = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "Work",
            appleCalendarDefaultSpace: "School",
            googleTwoWaySync: true,
            textScale: 1.15,
            sidebarMode: "hover",
            tasksGrouping: "dueDate",   // phone-owned: must NOT map to a local key
            perTabDocsSync: true,
            notificationPrefsJSON: "{\"a\":1}"
        )
        let byKey = Dictionary(uniqueKeysWithValues:
            SettingsSyncService.applies(from: row).map { ($0.key, $0.value) })

        XCTAssertEqual(byKey["tasks.defaultSpaceName"], .string("Work"))
        XCTAssertEqual(byKey["calendar.apple.defaultSpace"], .string("School"))
        XCTAssertEqual(byKey["calendar.google.enabled"], .bool(true))
        XCTAssertEqual(byKey["appearance.textScale"], .double(1.15))
        XCTAssertEqual(byKey["sidebar.mode"], .string("hover"))
        XCTAssertEqual(byKey["notes.perTabDocsSync.enabled"], .bool(true))
        XCTAssertEqual(byKey["notificationPrefs"], .string("{\"a\":1}"),
                       "notificationPrefs IS applied locally — the Mac-notifications task consumes it")
        XCTAssertNil(byKey["tasksGrouping"], "tasksGrouping has no Mac consumer — no local mapping")
        XCTAssertEqual(byKey.count, 7)
    }

    func testAppliesSkipsNilColumns() {
        let row = UserSettingsRow(userId: uid, sidebarMode: "always")
        XCTAssertEqual(SettingsSyncService.applies(from: row),
                       [.init(key: "sidebar.mode", value: .string("always"))])
    }

    // MARK: - readLocal(from:) — absent vs present

    func testReadLocalDistinguishesAbsentFromPresent() {
        let d = makeDefaults()
        d.set("Work", forKey: "tasks.defaultSpaceName")
        d.set(false, forKey: "calendar.google.enabled")   // present + false
        d.set("", forKey: "calendar.apple.defaultSpace")   // present + empty string

        let snap = SettingsSyncService.readLocal(from: d)
        XCTAssertEqual(snap.defaultSpaceName, "Work")
        XCTAssertEqual(snap.googleTwoWaySync, false)        // present false ≠ nil
        XCTAssertEqual(snap.appleCalendarDefaultSpace, "")  // present empty ≠ nil
        XCTAssertNil(snap.textScale)                        // absent, NOT 0.0
        XCTAssertNil(snap.perTabDocsSync)                   // absent, NOT false
        XCTAssertNil(snap.sidebarMode)
        XCTAssertNil(snap.notificationPrefsJSON)
    }

    // MARK: - mergedRow — overlay preserving phone-owned columns

    func testMergedRowOverlaysLocalAndPreservesPhoneOwnedColumns() {
        let base = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "Personal",
            sidebarMode: "always",
            tasksGrouping: "dueDate",                       // phone-owned, no Mac UI
            notificationPrefsJSON: "{\"morning\":true}"     // phone-owned
        )
        // User changed only sidebar.mode on the Mac.
        let local = SettingsSyncService.LocalSnapshot(sidebarMode: "hover")
        let out = SettingsSyncService.mergedRow(base: base, local: local, userId: uid)

        XCTAssertEqual(out.sidebarMode, "hover")                        // overlaid
        XCTAssertEqual(out.defaultSpaceName, "Personal")                // from base
        XCTAssertEqual(out.tasksGrouping, "dueDate")                    // preserved
        XCTAssertEqual(out.notificationPrefsJSON, "{\"morning\":true}") // preserved
        XCTAssertEqual(out.userId, uid)
    }

    func testMergedRowLocalWinsOverBase() {
        let base = UserSettingsRow(userId: uid, googleTwoWaySync: false, textScale: 1.0)
        let local = SettingsSyncService.LocalSnapshot(googleTwoWaySync: true, textScale: 1.3)
        let out = SettingsSyncService.mergedRow(base: base, local: local, userId: uid)
        XCTAssertEqual(out.textScale, 1.3)
        XCTAssertEqual(out.googleTwoWaySync, true)
    }

    func testMergedRowWithNilBaseUsesOnlyLocal() {
        let local = SettingsSyncService.LocalSnapshot(defaultSpaceName: "Work", sidebarMode: "hover")
        let out = SettingsSyncService.mergedRow(base: nil, local: local, userId: uid)
        XCTAssertEqual(out.defaultSpaceName, "Work")
        XCTAssertEqual(out.sidebarMode, "hover")
        XCTAssertNil(out.tasksGrouping)
        XCTAssertNil(out.textScale)
        XCTAssertEqual(out.userId, uid)
    }

    // MARK: - round-trip: apply a pulled row, read it back, rebuild the push row

    func testApplyThenReadRebuildsTheSameRow() {
        let d = makeDefaults()
        let server = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "Work",
            appleCalendarDefaultSpace: "School",
            googleTwoWaySync: true,
            textScale: 1.15,
            sidebarMode: "hover",
            tasksGrouping: "project",
            perTabDocsSync: true,
            notificationPrefsJSON: "{\"x\":1}"
        )
        for w in SettingsSyncService.applies(from: server) { w.apply(to: d) }
        let snap = SettingsSyncService.readLocal(from: d)
        let back = SettingsSyncService.mergedRow(base: server, local: snap, userId: uid)
        XCTAssertEqual(back, server)
    }

    // MARK: - isRedundantPush — pull-triggered pushes must be skipped

    /// The pull-triggered-push scenario end to end: a pull applies server values to
    /// defaults, `.onChange` fires and schedules a push — the row that push would
    /// send must be recognized as redundant and skipped.
    func testPullTriggeredPushIsRedundant() {
        let d = makeDefaults()
        var server = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "Work",
            googleTwoWaySync: true,
            textScale: 1.15,
            sidebarMode: "hover",
            tasksGrouping: "project"    // phone-owned; survives via mergedRow's base
        )
        server.updatedAt = Date()       // server rows carry updated_at; must not defeat the skip
        for w in SettingsSyncService.applies(from: server) { w.apply(to: d) }

        let merged = SettingsSyncService.mergedRow(
            base: server, local: SettingsSyncService.readLocal(from: d), userId: uid)
        XCTAssertTrue(SettingsSyncService.isRedundantPush(merged, lastPulled: server))
    }

    func testIsRedundantPushFalseWhenAFieldDiffers() {
        let pulled = UserSettingsRow(userId: uid, sidebarMode: "hover", tasksGrouping: "project")
        var changed = pulled
        changed.sidebarMode = "always"   // a real user change
        XCTAssertFalse(SettingsSyncService.isRedundantPush(changed, lastPulled: pulled))
    }

    func testIsRedundantPushFalseWithoutAPulledBaseline() {
        let row = UserSettingsRow(userId: uid, sidebarMode: "hover")
        XCTAssertFalse(SettingsSyncService.isRedundantPush(row, lastPulled: nil),
                       "No baseline ⇒ can't prove redundancy ⇒ push")
    }
}
