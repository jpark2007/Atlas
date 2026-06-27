import XCTest
import SwiftUI
@testable import Atlas

/// TDD for ShortcutStore:
/// Step 1 (RED) — these fail because ShortcutStore / ShortcutBinding / ShortcutAction
///               don't exist yet.
/// Step 2 (GREEN) — pass after Atlas/Services/ShortcutStore.swift is added.
final class ShortcutStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "test.ShortcutStore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default values

    func testDefaultCaptureIsCommandShiftK() {
        let store = ShortcutStore(defaults: defaults)
        let b = store.binding(for: .capture)
        XCTAssertEqual(b.key, "k")
        XCTAssertTrue(b.modifiers.contains(.command))
        XCTAssertTrue(b.modifiers.contains(.shift))
        XCTAssertFalse(b.modifiers.contains(.option))
    }

    func testDefaultSearchIsCommandK() {
        let store = ShortcutStore(defaults: defaults)
        let b = store.binding(for: .search)
        XCTAssertEqual(b.key, "k")
        XCTAssertTrue(b.modifiers.contains(.command))
        XCTAssertFalse(b.modifiers.contains(.shift))
        XCTAssertFalse(b.modifiers.contains(.option))
    }

    // MARK: - Set and read back

    func testSetBindingKeyAndModifiers() {
        let store = ShortcutStore(defaults: defaults)
        let newBinding = ShortcutBinding(key: "j", modifiers: [.command, .option])
        store.set(newBinding, for: .search)

        let readBack = store.binding(for: .search)
        XCTAssertEqual(readBack.key, "j")
        XCTAssertTrue(readBack.modifiers.contains(.command))
        XCTAssertTrue(readBack.modifiers.contains(.option))
        XCTAssertFalse(readBack.modifiers.contains(.shift))
    }

    // MARK: - Persistence (round-trip via fresh ShortcutStore)

    func testPersistenceAcrossInstances() {
        let store1 = ShortcutStore(defaults: defaults)
        store1.set(ShortcutBinding(key: "j", modifiers: [.command, .option]), for: .search)

        // A brand-new store reading the same UserDefaults suite must reconstruct the binding.
        let store2 = ShortcutStore(defaults: defaults)
        let b = store2.binding(for: .search)
        XCTAssertEqual(b.key, "j")
        XCTAssertTrue(b.modifiers.contains(.command))
        XCTAssertTrue(b.modifiers.contains(.option))
        XCTAssertFalse(b.modifiers.contains(.shift))
    }

    func testPersistenceCaptureDefaultSurvives() {
        // Writing search doesn't corrupt capture default.
        let store1 = ShortcutStore(defaults: defaults)
        store1.set(ShortcutBinding(key: "j", modifiers: [.command]), for: .search)

        let store2 = ShortcutStore(defaults: defaults)
        let cap = store2.binding(for: .capture)
        XCTAssertEqual(cap.key, "k")
        XCTAssertTrue(cap.modifiers.contains(.command))
        XCTAssertTrue(cap.modifiers.contains(.shift))
    }

    // MARK: - KeyEquivalent

    func testKeyEquivalentMatchesCharacter() {
        let b = ShortcutBinding(key: "j", modifiers: [.command])
        XCTAssertEqual(b.keyEquivalent, KeyEquivalent("j"))
    }

    // MARK: - displayString

    func testDisplayStringCommandK() {
        let b = ShortcutBinding(key: "k", modifiers: [.command])
        XCTAssertTrue(b.displayString.contains("⌘"))
        XCTAssertTrue(b.displayString.contains("K") || b.displayString.contains("k"))
    }

    func testDisplayStringCommandShiftK() {
        let b = ShortcutBinding(key: "k", modifiers: [.command, .shift])
        XCTAssertTrue(b.displayString.contains("⌘"))
        XCTAssertTrue(b.displayString.contains("⇧"))
        XCTAssertTrue(b.displayString.contains("K") || b.displayString.contains("k"))
    }

    func testDisplayStringCommandOptionJ() {
        let b = ShortcutBinding(key: "j", modifiers: [.command, .option])
        XCTAssertTrue(b.displayString.contains("⌘"))
        XCTAssertTrue(b.displayString.contains("⌥"))
        XCTAssertTrue(b.displayString.contains("J") || b.displayString.contains("j"))
    }

    // MARK: - Conflict detection

    func testConflictDetectedWhenComboMatches() {
        let store = ShortcutStore(defaults: defaults)
        // Rebind search to ⌘J …
        store.set(ShortcutBinding(key: "j", modifiers: [.command]), for: .search)

        // … then check if ⌘J conflicts when we're about to assign it to capture.
        let candidate = ShortcutBinding(key: "j", modifiers: [.command])
        let conflict = store.conflict(candidate, excluding: .capture)
        XCTAssertEqual(conflict, .search)
    }

    func testNoConflictWhenExcludingSelf() {
        let store = ShortcutStore(defaults: defaults)
        // search's own binding should NOT report a conflict when excluding search.
        let b = store.binding(for: .search)
        let conflict = store.conflict(b, excluding: .search)
        XCTAssertNil(conflict)
    }

    func testNoConflictForDistinctCombos() {
        let store = ShortcutStore(defaults: defaults)
        // ⌘⇧J doesn't match any default (⌘K / ⌘⇧K).
        let candidate = ShortcutBinding(key: "j", modifiers: [.command, .shift])
        let conflict = store.conflict(candidate, excluding: .search)
        XCTAssertNil(conflict)
    }

    // MARK: - Reset

    func testResetRestoresDefault() {
        let store = ShortcutStore(defaults: defaults)
        store.set(ShortcutBinding(key: "j", modifiers: [.command, .option]), for: .search)
        store.reset(.search)

        let b = store.binding(for: .search)
        XCTAssertEqual(b.key, "k")
        XCTAssertTrue(b.modifiers.contains(.command))
        XCTAssertFalse(b.modifiers.contains(.option))
    }

    func testResetPersists() {
        let store1 = ShortcutStore(defaults: defaults)
        store1.set(ShortcutBinding(key: "j", modifiers: [.command, .option]), for: .search)
        store1.reset(.search)

        let store2 = ShortcutStore(defaults: defaults)
        let b = store2.binding(for: .search)
        XCTAssertEqual(b.key, "k")
        XCTAssertTrue(b.modifiers.contains(.command))
        XCTAssertFalse(b.modifiers.contains(.option))
    }

    // MARK: - ShortcutAction metadata

    func testAllCasesCount() {
        XCTAssertEqual(ShortcutAction.allCases.count, 2)
    }

    func testActionTitles() {
        XCTAssertFalse(ShortcutAction.capture.title.isEmpty)
        XCTAssertFalse(ShortcutAction.search.title.isEmpty)
    }
}
