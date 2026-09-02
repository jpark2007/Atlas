import Foundation

/// Handoff §C4: **accepting a scan must never duplicate an existing Canvas task or
/// calendar event.**
///
/// Canvas and the syllabus describe the same work in different words on the same day —
/// "Lecture 4 The Chain Rule" vs "The chain rule" — so neither exact titles nor exact
/// instants find the pair. What is reliable is *same class + a shared distinctive run of
/// title + the same or an adjacent calendar day*. Matched rows are un-checked and badged,
/// never dropped: the student always sees what the scan found and can accept it anyway.
///
/// Pure and shared so Mac and iOS mark identical rows.
public enum SyllabusDedupe {

    /// Shortest run of normalized title two rows must share to be considered the same
    /// work. Eight characters is `CalendarSync.minPrefixMatchLength` — long enough that
    /// "lecture" (7) can never be the whole of a match.
    static let minSharedRun = 8

    /// The shared run must also be at least half of the shorter title, so "lecture1…" and
    /// "lecture10…" (8 shared characters, different assignments) never collide.
    static let minSharedFraction = 0.5

    /// Days apart two dates may be and still describe the same work. Canvas dates a
    /// lecture on the day it is given; a syllabus often states the next day's deadline.
    static let dayTolerance = 1

    /// The review rows, with every item that already exists on its target class
    /// un-checked and flagged. Nothing is removed.
    ///
    /// Authoritative over both flags, so re-running it after a group is re-targeted at a
    /// different class re-decides cleanly instead of leaving a stale badge behind.
    ///
    /// `tasks`/`events` are the user's full pools; each group is compared only against the
    /// items filed under the class it commits onto — matching across classes would collapse
    /// two different courses' "Midterm 1".
    public static func markingExisting(_ groups: [SyllabusDraftGroup],
                                       tasks: [TaskItem],
                                       events: [CalendarEvent],
                                       calendar: Calendar = .current) -> [SyllabusDraftGroup] {
        groups.map { group in
            guard let target = group.targetClassID else { return group }
            let classTasks  = tasks.filter  { $0.projectID == target }
                                   .map { ($0.title, $0.effectiveDueDate(calendar: calendar)) }
            // `bucketDate`, not `start`: a syllabus-committed exam is an all-day event on
            // the canonical UTC anchor, which reads as the previous day west of Greenwich.
            let classEvents = events.filter { $0.projectID == target }
                                    .map { ($0.title, Optional($0.bucketDate(in: calendar))) }

            var marked = group
            marked.items = group.items.map { item in
                let pool = item.kind == .event ? classEvents : classTasks
                let hit = pool.contains { matches(draftTitle: item.title, draftDate: item.date,
                                                  existingTitle: $0.0, existingDate: $0.1,
                                                  calendar: calendar) }
                var item = item
                item.alreadyExists = hit
                item.include = !hit
                return item
            }
            return marked
        }
    }

    /// Whether a draft row and an existing item are the same piece of work.
    ///
    /// Title: `CalendarSync`'s equality/prefix rule first, then a shared distinctive run
    /// (the wording differs, the topic doesn't). Date: the same or an adjacent calendar
    /// DAY — deliberately not the same instant, because Canvas's 11:59 PM and the
    /// syllabus's stated hour never agree to the second. A draft with no date can only
    /// match on the title.
    public static func matches(draftTitle: String, draftDate: Date?,
                               existingTitle: String, existingDate: Date?,
                               calendar: Calendar = .current) -> Bool {
        guard titlesDescribeSameWork(draftTitle, existingTitle) else { return false }
        // Undated on either side: the title match is all there is to go on, and it stands.
        guard let draftDate, let existingDate else { return true }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: draftDate),
                                           to: calendar.startOfDay(for: existingDate)).day ?? 0
        return abs(days) <= dayTolerance
    }

    /// Title agreement, normalized: `CalendarSync`'s own rule, widened by a shared-run test
    /// for the case that rule was never built for — a Canvas title that PREFIXES the topic
    /// ("Lecture 4 The Chain Rule") against the syllabus's bare wording ("The chain rule").
    /// Then, last, the word-order test a course SCHEDULE needs: the schedule prints
    /// "DBQ Module 5", Canvas names the same work "Module 5 DBQ".
    static func titlesDescribeSameWork(_ a: String, _ b: String) -> Bool {
        let ka = CalendarSync.normalizeTitle(a), kb = CalendarSync.normalizeTitle(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        if CalendarSync.titlesMatch(ka, kb) { return true }
        let shorter = min(ka.count, kb.count)
        let run = longestSharedRun(Array(ka), Array(kb))
        if run >= minSharedRun && Double(run) >= Double(shorter) * minSharedFraction { return true }
        return wordsDescribeSameWork(a, b)
    }

    /// Order-insensitive agreement, for the titles a schedule document produces: the same
    /// words in a different order, or with the extra words a Canvas assignment carries
    /// ("Module 5 DBQ" vs "DBQ Module 5 — Due in Canvas").
    ///
    /// Strict on purpose, because word bags collide easily: one side's distinctive words
    /// must be wholly contained in the other's, both sides must carry at least two, and
    /// **every number must agree** — "Module 5 DBQ" and "Module 6 DBQ" are different work
    /// and share everything but the digit.
    static func wordsDescribeSameWork(_ a: String, _ b: String) -> Bool {
        let wa = distinctiveWords(a), wb = distinctiveWords(b)
        guard wa.count >= 2, wb.count >= 2 else { return false }
        let (smaller, larger) = wa.count <= wb.count ? (wa, wb) : (wb, wa)
        guard smaller.isSubset(of: larger) else { return false }
        let numbers: (Set<String>) -> Set<String> = { $0.filter { $0.allSatisfy(\.isNumber) } }
        return numbers(wa) == numbers(wb)
    }

    /// Words that carry meaning, normalized so "DBQ's" and "DBQ" are one word — lowercased,
    /// depunctuated, de-pluralized, with the filler a title picks up on its way through
    /// Canvas dropped. "Midterm" folds to "exam": a schedule that prints both an "Exam 1"
    /// column and a "Midterm 1" title is naming one sitting, not two.
    static func distinctiveWords(_ title: String) -> Set<String> {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return Set(words.compactMap { raw -> String? in
            let word = String(raw)
            let singular = word.count >= 4 && word.hasSuffix("s") ? String(word.dropLast()) : word
            guard !stopWords.contains(word), !stopWords.contains(singular) else { return nil }
            return singular == "midterm" ? "exam" : singular
        })
    }

    /// Words that say nothing about WHICH piece of work this is.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "of", "for", "in", "on", "and", "to", "at", "by",
        "due", "assignment", "submit", "submission", "canvas", "online", "required",
    ]

    /// Length of the longest substring `a` and `b` share. Titles are short, so the plain
    /// rolling DP is the right amount of machinery.
    private static func longestSharedRun(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var best = 0
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            for j in 1...b.count where a[i - 1] == b[j - 1] {
                current[j] = previous[j - 1] + 1
                best = max(best, current[j])
            }
            previous = current
        }
        return best
    }
}
