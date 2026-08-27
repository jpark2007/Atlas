import Foundation

/// Pure reconciliation helpers for Atlas ⇄ Google calendar sync. Deliberately free of
/// network and app state so the data-loss-critical rules can be unit-tested in isolation.
public enum CalendarSync {

    /// True when an Atlas-origin event should be mirrored into Apple Calendar. Pure gate
    /// (no EventKit / app-state access) so the decision is unit-testable; the live caller
    /// supplies the device-local toggle + EventKit authorization. Work-blocks never reach
    /// here — the mirror trio only sees first-class `events`, matching the Google trio.
    public static func shouldWriteBackApple(
        enabled: Bool,
        authorized: Bool,
        event: CalendarEvent
    ) -> Bool {
        guard enabled, authorized else { return false }
        // Task 12 adds: && event.rrule == nil  (recurring events aren't mirrored)
        return event.source == .atlas && !event.isReadOnly
    }

    /// External (read-only) events to display after dropping any that are actually our own
    /// mirrors already shown natively: a Google event we pushed (matched by `googleEventId`)
    /// or an Apple event we mirrored (matched by `appleEventId`, which EventKit re-reads on
    /// the next tick). Without this, every mirrored event double-displays — once as the
    /// native Atlas tile, once as its external copy.
    public static func excludingOwnMirrors(
        external: [CalendarEvent],
        ownGoogleIDs: Set<String>,
        ownAppleIDs: Set<String>
    ) -> [CalendarEvent] {
        external.filter { ev in
            if let gid = ev.googleEventId, ownGoogleIDs.contains(gid) { return false }
            if let aid = ev.appleEventId, ownAppleIDs.contains(aid) { return false }
            return true
        }
    }

    /// Deterministic UUID (FNV-1a) from an external/synthesized event key, so a re-fetch or
    /// re-render reuses the same id instead of flickering. Byte-identical to
    /// `GoogleCalendarMapper.stableUUID` / `EventKitService.stableUUID` — the same key must
    /// always give the same id, on every platform.
    public static func stableUUID(from identifier: String) -> UUID {
        var h: UInt64 = 14695981039346656037
        for byte in identifier.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        let h2 = h.byteSwapped
        return UUID(uuid: (
            UInt8((h >> 56) & 0xFF), UInt8((h >> 48) & 0xFF),
            UInt8((h >> 40) & 0xFF), UInt8((h >> 32) & 0xFF),
            UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF),
            UInt8((h >>  8) & 0xFF), UInt8( h         & 0xFF),
            UInt8((h2 >> 56) & 0xFF), UInt8((h2 >> 48) & 0xFF),
            UInt8((h2 >> 40) & 0xFF), UInt8((h2 >> 32) & 0xFF),
            UInt8((h2 >> 24) & 0xFF), UInt8((h2 >> 16) & 0xFF),
            UInt8((h2 >>  8) & 0xFF), UInt8( h2         & 0xFF)
        ))
    }

    // MARK: - Outbound push rules

    /// The default mirror prefix put on work sessions pushed to Google/Apple, and the
    /// value dedup strips before comparing titles. Human-readable by design.
    public static let defaultWorkSessionPrefix = "Work: "

    /// The title a work session wears on an external calendar. Reserved time IS busy time,
    /// but an external calendar can't carry Atlas's "planned work" styling — so the session
    /// says what it is in words. Idempotent: a title that already carries the prefix (a
    /// re-push, or a task the user named that way) is never double-prefixed.
    public static func mirroredWorkSessionTitle(
        _ taskTitle: String,
        prefix: String = defaultWorkSessionPrefix
    ) -> String {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return trimmed }
        let key = normalizeTitle(prefix)
        guard !key.isEmpty, !normalizeTitle(trimmed).hasPrefix(key) else { return trimmed }
        return prefix + trimmed
    }

    // MARK: - Cross-calendar dedup

    /// Minimum normalized-title length for the prefix-tolerant match ("English essay"
    /// vs "English essay draft"). Below it, only an exact normalized match counts —
    /// short titles like "Lab" or "Gym" are far too collision-prone to shorten.
    private static let minPrefixMatchLength = 8

    /// Start instants this far apart still count as "the same start" — feeds and Google
    /// disagree by seconds on the same block, never by a minute.
    private static let sameStartTolerance: TimeInterval = 60

    /// For same-day events that don't share a start: the overlap must cover at least this
    /// share of the SHORTER event for them to be one block. Deliberately high — the spec's
    /// rule is "when unsure, show both".
    private static let overlapThreshold: Double = 0.5

    /// Collapses the same real-world block arriving from several calendars into one tile.
    ///
    /// Runs client-side at display time over the already-merged native + external pool —
    /// required, because Apple events are never persisted (they're in-memory per view), so
    /// no server pass can see them. Pure and shared so Mac and iOS render the identical
    /// collapsed pool.
    ///
    /// Match rule: normalized-title equality (case/whitespace/punctuation-insensitive,
    /// tolerant of the work-session mirror prefix and of one title extending the other)
    /// AND time agreement (same start, or same-day overlap past `overlapThreshold`).
    ///
    /// Winner order: Atlas-native > Google > Apple/Canvas/ICS — prefer the writable copy.
    /// Losers are hidden, never deleted; the winner carries their `source`s in
    /// `duplicateSources` so the detail view can show an "also in …" note. Source
    /// attribution is never rewritten — each event keeps the source it was ingested with.
    public static func collapsingDuplicates(
        _ events: [CalendarEvent],
        workSessionPrefix: String = defaultWorkSessionPrefix,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let normalizedPrefix = normalizeTitle(workSessionPrefix)
        let keys = events.map { normalizeTitle($0.title, strippingPrefix: normalizedPrefix) }

        var absorbed = Array(repeating: false, count: events.count)
        var extraSources = Array(repeating: [EventSource](), count: events.count)

        for i in events.indices {
            // Deadline pills are Atlas-only markers, never a second copy of anything —
            // collapsing one into the work session for the same task would lose the due flag.
            guard !absorbed[i], !events[i].isDeadline else { continue }
            for j in (i + 1)..<events.count where !absorbed[j] && !events[j].isDeadline {
                guard titlesMatch(keys[i], keys[j]),
                      timesMatch(events[i], events[j], calendar: calendar) else { continue }
                // Winner keeps its own index slot; the loser is hidden behind it.
                let iWins = priority(events[i].source) <= priority(events[j].source)
                let winner = iWins ? i : j
                let loser = iWins ? j : i
                absorbed[loser] = true
                extraSources[winner].append(contentsOf: extraSources[loser])
                extraSources[loser] = []
                extraSources[winner].append(events[loser].source)
                if loser == i { break } // i is gone; move on to the next event
            }
        }

        return events.indices.compactMap { i -> CalendarEvent? in
            guard !absorbed[i] else { return nil }
            var winner = events[i]
            winner.duplicateSources = extraSources[i].filter { $0 != winner.source }.reduce(into: []) {
                if !$0.contains($1) { $0.append($1) }
            }
            return winner
        }
    }

    /// Never collapse two events whose titles only *look* alike: equality after
    /// normalization, or one title extending the other once both are long enough to be
    /// distinctive.
    private static func titlesMatch(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
        guard shorter.count >= minPrefixMatchLength else { return false }
        return longer.hasPrefix(shorter)
    }

    private static func timesMatch(_ a: CalendarEvent, _ b: CalendarEvent, calendar: Calendar) -> Bool {
        // All-day events are floating dates, not instants (see `AllDayDate`): two copies of the
        // same holiday agree when they name the same calendar date, and instant proximity says
        // nothing useful about them. A mixed pair never matches — "Labor Day" the flag and a
        // meeting named "Labor Day" are different things, however much they overlap.
        if a.isAllDay || b.isAllDay {
            guard a.isAllDay, b.isAllDay else { return false }
            return AllDayDate.utcDay(of: a.start) == AllDayDate.utcDay(of: b.start)
        }
        if abs(a.start.timeIntervalSince(b.start)) <= sameStartTolerance { return true }
        guard calendar.isDate(a.start, inSameDayAs: b.start) else { return false }
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        guard overlap > 0 else { return false }
        let shortest = min(a.end.timeIntervalSince(a.start), b.end.timeIntervalSince(b.start))
        guard shortest > 0 else { return false }
        return overlap / shortest >= overlapThreshold
    }

    /// Lower wins. Atlas-native first (it's the writable copy), then Google, then the
    /// read-only feeds — no source is ever relabelled, only ranked.
    private static func priority(_ source: EventSource) -> Int {
        switch source {
        case .atlas: return 0
        case .google: return 1
        case .apple, .canvas, .icsFeed: return 2
        }
    }

    /// Case/whitespace/punctuation-insensitive title key: "BIO 201 Lecture" and
    /// "BIO201 - Lecture" both reduce to "bio201lecture", while "BIO 301 Lecture" doesn't.
    /// A leading work-session mirror prefix is dropped so "Work: English essay" coming
    /// back inbound keys the same as the native session it mirrors.
    static func normalizeTitle(_ title: String, strippingPrefix prefix: String = "") -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var key = String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        if !prefix.isEmpty, key.hasPrefix(prefix), key.count > prefix.count {
            key.removeFirst(prefix.count)
        }
        return key
    }
}
