import SwiftUI
import TipKit

// MARK: - Shared donation events
//
// One event per "user did the thing". Donated at real call sites (see Mac Task 2,
// iOS Task 6). Tips read them in #Rule closures to self-retire or to gate display.

public enum AtlasTipEvents {
    public static let openedApp        = Tips.Event(id: "atlas.openedApp")
    public static let usedSearch       = Tips.Event(id: "atlas.usedSearch")
    public static let scheduledByDrag  = Tips.Event(id: "atlas.scheduledByDrag")
    public static let connectedSource  = Tips.Event(id: "atlas.connectedSource")
    public static let captured         = Tips.Event(id: "atlas.captured")
    public static let openedNote       = Tips.Event(id: "atlas.openedNote")
    public static let sawFrozenIsland  = Tips.Event(id: "atlas.sawFrozenIsland")
    public static let invited          = Tips.Event(id: "atlas.invited")
    public static let usedGlobalCapture = Tips.Event(id: "atlas.usedGlobalCapture")
    public static let scheduledOnCalendar = Tips.Event(id: "atlas.scheduledOnCalendar")
    public static let peekedMonth      = Tips.Event(id: "atlas.peekedMonth")
    public static let reportedBug      = Tips.Event(id: "atlas.reportedBug")
}

// MARK: - Tips

public enum AtlasTips {

    /// 1 — ⌘K command palette (Mac only). Rule: app opened ≥2 times AND search never used.
    public struct CommandPalette: Tip {
        @Parameter public static var appOpens: Int = 0
        public init() {}
        public var title: Text { Text("Jump anywhere") }
        public var message: Text? { Text("Press ⌘K to search notes, classes, and commands from anywhere") }
        public var image: Image? { Image(systemName: "magnifyingglass") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 2 }
            #Rule(AtlasTipEvents.usedSearch) { $0.donations.count == 0 }
        }
    }

    /// 2 — Drag-to-schedule (both). Rule: first calendar visit AND ≥1 unscheduled task.
    public struct DragToSchedule: Tip {
        @Parameter public static var hasUnscheduled: Bool = false
        public init() {}
        public var title: Text { Text("Block time for it") }
        #if os(macOS)
        public var message: Text? { Text("Drag a task from the tray onto the grid to schedule it") }
        #else
        public var message: Text? { Text("Tap a task in “Needs a time”, then place it on the day") }
        #endif
        public var image: Image? { Image(systemName: "hand.draw") }
        public var rules: [Rule] {
            #Rule(Self.$hasUnscheduled) { $0 == true }
            #if os(macOS)
            #Rule(AtlasTipEvents.scheduledByDrag) { $0.donations.count == 0 }
            #else
            #Rule(AtlasTipEvents.scheduledOnCalendar) { $0.donations.count == 0 }
            #endif
        }
    }

    /// 3 — Connect Google/Canvas (both). Rule: app opened ≥3 times AND nothing connected.
    public struct ConnectSource: Tip {
        @Parameter public static var appOpens: Int = 0
        @Parameter public static var hasConnection: Bool = false
        public init() {}
        public var title: Text { Text("Bring in your calendar") }
        public var message: Text? { Text("Connect Google or Canvas to see everything in one place") }
        public var image: Image? { Image(systemName: "link") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 3 }
            #Rule(Self.$hasConnection) { $0 == false }
            #Rule(AtlasTipEvents.connectedSource) { $0.donations.count == 0 }
        }
    }

    /// 4 — Per-calendar checkboxes (Mac only). Rule: shown inside the auto-opened
    /// connection sheet on first connect. Gated entirely by its anchor appearing;
    /// no extra rule beyond "not yet dismissed".
    public struct PerCalendarPicker: Tip {
        public init() {}
        public var title: Text { Text("Pick what syncs") }
        public var message: Text? { Text("Turn calendars on or off — only the checked ones show in Atlas") }
        public var image: Image? { Image(systemName: "checklist") }
    }

    /// 5 — Report a Bug (both, beta only). Rule: app opened ≥4 times.
    /// Beta-only gating is applied at the ANCHOR with `if AtlasBuild.isBeta` (Task 2/6),
    /// so no rule is needed here beyond the session count.
    public struct ReportBug: Tip {
        @Parameter public static var appOpens: Int = 0
        public init() {}
        public var title: Text { Text("Hit a snag?") }
        public var message: Text? { Text("Send it straight to us from here — no email needed") }
        public var image: Image? { Image(systemName: "ant") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 4 }
            #Rule(AtlasTipEvents.reportedBug) { $0.donations.count == 0 }
        }
    }

    /// 6 — Global capture reminder (Mac only). Rule: app opened ≥3 times AND
    /// the global capture key has never been used.
    public struct GlobalCapture: Tip {
        @Parameter public static var appOpens: Int = 0
        public init() {}
        public var title: Text { Text("Capture from any app") }
        public var message: Text? { Text("Press ⌘⇧K from anywhere to jot a task or speak it") }
        public var image: Image? { Image(systemName: "bolt") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 3 }
            #Rule(AtlasTipEvents.usedGlobalCapture) { $0.donations.count == 0 }
        }
    }

    /// 7 — Doc tabs basics (Mac only). Rule: first time inside a note that has tabs.
    public struct DocTabs: Tip {
        public init() {}
        public var title: Text { Text("Switch between tabs") }
        public var message: Text? { Text("This note has more than one tab — tap to move between them") }
        public var image: Image? { Image(systemName: "doc.on.doc") }
    }

    /// 8 — Drive sync (Mac only). Rule: gated at the anchor (first note in a
    /// Drive-linked project AND Google connected).
    public struct DriveSync: Tip {
        public init() {}
        public var title: Text { Text("Kept in sync with Drive") }
        public var message: Text? { Text("Edits here round-trip to the linked Google Doc") }
        public var image: Image? { Image(systemName: "arrow.triangle.2.circlepath") }
    }

    /// 9 — Frozen islands (Mac only). Rule: first time an island is visible.
    public struct FrozenIslands: Tip {
        public init() {}
        public var title: Text { Text("Frozen from Google") }
        public var message: Text? { Text("Shaded blocks are read-only content Atlas keeps exactly as Google has it") }
        public var image: Image? { Image(systemName: "lock.doc") }
        public var rules: [Rule] {
            #Rule(AtlasTipEvents.sawFrozenIsland) { $0.donations.count == 0 }
        }
    }

    /// 10 — Invite people (Mac only). Rule: gated at the anchor (on a space page
    /// AND the user is the only member).
    public struct InvitePeople: Tip {
        public init() {}
        public var title: Text { Text("Bring someone in") }
        public var message: Text? { Text("Invite a teammate to share this space") }
        public var image: Image? { Image(systemName: "person.badge.plus") }
        public var rules: [Rule] {
            #Rule(AtlasTipEvents.invited) { $0.donations.count == 0 }
        }
    }

    /// Call once per app at launch, before any tip renders. Wraps `Tips.configure`
    /// and bumps the shared `appOpens` counters used by rules 1/3/5/6.
    public static func configureOnce() {
        #if DEBUG
        // ---------------------------------------------------------------------
        // QA POINTER — force-show every tip (Debug only)
        //
        // Leave this COMMENTED for normal Debug runs so rule/session timing works
        // as shipped. To sweep all ten tips at once (ignoring #Rule gating, session
        // counts, and prior dismissals), uncomment the single line below and run a
        // Debug build. Re-comment before committing — no committed file may ship
        // with it enabled. It is compiled out of Release entirely.
        // ---------------------------------------------------------------------
        // Tips.showAllTipsForTesting()
        #endif
        try? Tips.configure([
            .displayFrequency(.immediate),   // rules already throttle; one-at-a-time is TipKit default UI behavior
            .datastoreLocation(.applicationDefault)
        ])
        bumpAppOpens()
    }

    private static func bumpAppOpens() {
        let next = min(CommandPalette.appOpens + 1, 99)
        CommandPalette.appOpens = next
        ConnectSource.appOpens = next
        ReportBug.appOpens = next
        GlobalCapture.appOpens = next
    }
}

// MARK: - Conditional tip helper

public extension View {
    /// Attach an onboarding tip only while `condition` holds — the macOS 14 / iOS 17-safe
    /// form of a conditional `.popoverTip` (the optional-tip overload needs macOS 26 / iOS 26).
    @ViewBuilder
    func onboardingTip(_ tip: some Tip, when condition: Bool, arrowEdge: Edge = .top) -> some View {
        if condition { popoverTip(tip, arrowEdge: arrowEdge) } else { self }
    }
}

public enum AtlasBuild {
    /// Beta across the board for v0.9 — the Report-a-bug tip fires on every build. Flip to
    /// false (or wire a real beta flag) at GA so the tip stops showing.
    public static var isBeta: Bool { true }
}
