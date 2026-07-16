import XCTest
@testable import AtlasCore

/// Tests for the platform-neutral settings-sync core shared by the Mac and iOS
/// `SettingsSyncService`s: the row overlay (preserve base, local wins) and the
/// redundant-push guard (skip a pull's own echo). Ported from the Mac
/// `SettingsSyncServiceTests` cases that covered these two functions.
final class UserSettingsMergeTests: XCTestCase {

    private let uid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    // MARK: - overlay(base:local:userId:)

    /// A device pushes only the columns it owns; every other column must survive
    /// from the last-pulled base (never nulled).
    func testOverlayLocalWinsAndPreservesUnsetBaseColumns() {
        let base = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "Personal",
            appleCalendarDefaultSpace: "School",   // owned by the other device
            sidebarMode: "always",                 // owned by the other device
            tasksGrouping: "dueDate",
            notificationPrefsJSON: "{\"morning\":true}"
        )
        // This device changed only tasks_grouping.
        let local = UserSettingsRow(userId: uid, tasksGrouping: "project")
        let out = UserSettingsMerge.overlay(base: base, local: local, userId: uid)

        XCTAssertEqual(out.tasksGrouping, "project")                    // overlaid
        XCTAssertEqual(out.defaultSpaceName, "Personal")               // from base
        XCTAssertEqual(out.appleCalendarDefaultSpace, "School")        // preserved
        XCTAssertEqual(out.sidebarMode, "always")                      // preserved
        XCTAssertEqual(out.notificationPrefsJSON, "{\"morning\":true}")// preserved
        XCTAssertEqual(out.userId, uid)
        XCTAssertNil(out.updatedAt, "the server stamps updated_at; never sent from the client")
    }

    func testOverlayLocalWinsOverBase() {
        let base = UserSettingsRow(userId: uid, textScale: 1.0, perTabDocsSync: false)
        let local = UserSettingsRow(userId: uid, textScale: 1.3, perTabDocsSync: true)
        let out = UserSettingsMerge.overlay(base: base, local: local, userId: uid)
        XCTAssertEqual(out.textScale, 1.3)
        XCTAssertEqual(out.perTabDocsSync, true)
    }

    func testOverlayWithNilBaseUsesOnlyLocal() {
        let local = UserSettingsRow(userId: uid, defaultSpaceName: "Work", sidebarMode: "hover")
        let out = UserSettingsMerge.overlay(base: nil, local: local, userId: uid)
        XCTAssertEqual(out.defaultSpaceName, "Work")
        XCTAssertEqual(out.sidebarMode, "hover")
        XCTAssertNil(out.tasksGrouping)
        XCTAssertNil(out.textScale)
        XCTAssertEqual(out.userId, uid)
    }

    // MARK: - isRedundantPush(_:lastPulled:)

    /// After a pull applies server values, the change echoes schedule a push whose
    /// row equals the last-pulled row — it must be recognized as redundant. The
    /// server-stamped `updatedAt` on the baseline must not defeat the skip.
    func testIsRedundantPushTrueWhenRowEqualsLastPulled() {
        var pulled = UserSettingsRow(
            userId: uid,
            defaultSpaceName: "Work",
            sidebarMode: "hover",
            tasksGrouping: "project"
        )
        pulled.updatedAt = Date()   // server rows carry updated_at
        // The overlay always drops updated_at, so the echo row has none.
        let echo = UserSettingsMerge.overlay(
            base: pulled,
            local: UserSettingsRow(userId: uid),   // no local change
            userId: uid)
        XCTAssertTrue(UserSettingsMerge.isRedundantPush(echo, lastPulled: pulled))
    }

    func testIsRedundantPushFalseWhenAFieldDiffers() {
        let pulled = UserSettingsRow(userId: uid, sidebarMode: "hover", tasksGrouping: "project")
        var changed = pulled
        changed.sidebarMode = "always"   // a real user change
        XCTAssertFalse(UserSettingsMerge.isRedundantPush(changed, lastPulled: pulled))
    }

    func testIsRedundantPushFalseWithoutAPulledBaseline() {
        let row = UserSettingsRow(userId: uid, sidebarMode: "hover")
        XCTAssertFalse(UserSettingsMerge.isRedundantPush(row, lastPulled: nil),
                       "No baseline ⇒ can't prove redundancy ⇒ push")
    }

    // MARK: - wire shape — nil columns are OMITTED, never explicit nulls

    /// The overlay's cross-device safety rests on this: a pushed row's nil columns
    /// (the other platform's) must be ABSENT from the upsert body — PostgREST's
    /// merge-duplicates leaves a column untouched only when its key is missing;
    /// an explicit `"col": null` would null it on the server.
    func testEncodingOmitsNilColumnsEntirely() throws {
        let row = UserSettingsRow(userId: uid, tasksGrouping: "project")
        let data = try JSONEncoder().encode(row)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["user_id", "tasks_grouping"],
                       "nil columns must be omitted from the JSON, not encoded as null")
    }
}
