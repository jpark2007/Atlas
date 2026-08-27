import SwiftUI
import AtlasCore

/// The iOS display pool and the Late-bar triage action — both built out of the SAME
/// shared AtlasCore functions the Mac uses, so the two platforms render the identical
/// collapsed set of blocks.
///
/// Additive extension on `MobileStore` (no restructuring): Apple Calendar events are the
/// one thing that never round-trips through the server (EventKit is per-device), so they
/// live in memory here and are merged at display time.
extension MobileStore {

    // MARK: - Apple Calendar (device-local, read only)

    /// Device-local connect flag. Apple Calendar is per-device by design — the Mac's
    /// connection is not this phone's, so this never syncs.
    static let appleEnabledKey = "calendar.apple.enabled"

    var appleCalendarEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.appleEnabledKey) }
        set {
            objectWillChange.send()          // it isn't @Published — nudge the views that read it
            UserDefaults.standard.set(newValue, forKey: Self.appleEnabledKey)
            if !newValue { appleEvents = [] }
        }
    }

    /// Request access, then load the first window. Returns false when the user declines
    /// (the row then points at iOS Settings — Atlas can't re-prompt after a denial).
    @discardableResult
    func connectAppleCalendar(around day: Date = Date()) async -> Bool {
        guard await eventKit.requestAccess() else {
            appleCalendarEnabled = false
            return false
        }
        appleCalendarEnabled = true
        refreshAppleEvents(around: day)
        return true
    }

    /// Reload the in-memory Apple pool for the window around `day`. Cheap (an on-device
    /// EventKit read), so it runs on connect, on every store refresh, on a day change, and
    /// whenever EventKit says the on-device store changed.
    func refreshAppleEvents(around day: Date) {
        guard appleCalendarEnabled, eventKit.hasAccess else {
            if !appleEvents.isEmpty { appleEvents = [] }
            return
        }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: day)) ?? day
        let end = cal.date(byAdding: .day, value: 8, to: cal.startOfDay(for: day)) ?? day
        let hidden = AppleCalendarSelection.decode(
            UserDefaults.standard.string(forKey: AppleCalendarSelection.hiddenKey) ?? "")
        appleEvents = eventKit.fetchEvents(start: start, end: end,
                                           defaultSpaceName: appleDefaultSpaceName,
                                           hiddenCalendarIds: hidden)
    }

    /// The space an Apple event lands in: the user's first space, so it renders in the
    /// filter like everything else. Its `source` stays `.apple` — attribution is never
    /// rewritten by the space it displays under.
    private var appleDefaultSpaceName: String {
        snapshot.spaces.first?.name ?? "Personal"
    }

    // MARK: - The display pool

    /// Everything the day's list/grid should draw: Atlas-native events, synthesized class
    /// meetings, read-only Apple events, and term Key Date flags — all run through the SAME
    /// shared pipeline as the Mac (`excludingOwnMirrors` → `collapsingDuplicates`).
    ///
    /// Key Date flags used to sit *outside* dedup, on the reasoning that a flag labels a day
    /// and is never a second copy of a block. That is now handled inside dedup instead: an
    /// all-day event matches only another all-day event on the same UTC calendar date, so a
    /// registrar "Labor Day" flag collapses with the Google/Apple copy of the same holiday
    /// (the whole point), while a pure label like "Add/drop ends" can never absorb a meeting.
    func displayEvents(on day: Date) -> [CalendarEvent] {
        // Drop any Apple event that is really one of our own mirrors, already shown natively.
        let ownAppleIDs = Set(snapshot.events.compactMap(\.appleEventId))
            .union(snapshot.tasks.compactMap(\.appleEventId))
        let external = CalendarSync.excludingOwnMirrors(external: appleEvents,
                                                        ownGoogleIDs: [],
                                                        ownAppleIDs: ownAppleIDs)
        let pool = snapshot.events + external + classMeetingEvents(on: day) + keyDateFlags(on: day)
        return CalendarSync.collapsingDuplicates(pool)
    }

    // MARK: - School synthesis (shared helpers)
    // `activeTerm` and `schoolEnabled` are declared in MobileStore+School.swift.

    /// Class meetings on `day`, from the active term's live classes.
    func classMeetingEvents(on day: Date) -> [CalendarEvent] {
        guard schoolEnabled, let term = activeTerm else { return [] }
        let classes = snapshot.projects.filter {
            $0.isClass && $0.termID == term.id && $0.archivedAt == nil
        }
        return SchoolCalendar.meetingEvents(on: day, classes: classes, term: term)
    }

    /// The active term's Key Dates on `day`, as all-day flags.
    func keyDateFlags(on day: Date) -> [CalendarEvent] {
        guard schoolEnabled, let term = activeTerm else { return [] }
        let space = snapshot.spaces.first { $0.name.caseInsensitiveCompare("School") == .orderedSame }
        return SchoolCalendar.keyDateFlagEvents(
            on: day, in: term,
            spaceName: space?.name ?? snapshot.spaces.first?.name ?? "School")
    }

    // MARK: - Late-bar triage

    /// "Reschedule N late items" — the Mac's action, from the shared pure function, so the
    /// original due dates survive identically on both platforms.
    func rescheduleLateItems(to date: Date) async {
        for updated in TimeModel.rescheduleLate(tasks: snapshot.tasks, to: date) {
            await updateTask(updated)
        }
    }
}
