import Foundation

/// Picking the student's section for them when the class ALREADY knows its schedule.
///
/// A syllabus lists every section of a course; the review sheet asks which one is yours
/// (§C1). But a class imported from the semester wizard's `.ics` already carries the one
/// the student actually attends in `project.meetingPattern` — so the question has an
/// answer before it is asked. Pure and shared so Mac and iOS pre-pick identically.
public enum SyllabusSectionMatch {

    /// How far a scanned start may sit from an existing meeting and still be the same
    /// block. A syllabus printing "9:30" against a registrar's "9:35" is not another
    /// section; half an hour apart is.
    public static let toleranceMinutes = 15

    /// The one scanned section that matches the class's existing schedule, or `nil` when
    /// zero or several do — an ambiguous answer is no answer, and the picker stands.
    public static func match(for group: SyllabusDraftGroup,
                             existing: [MeetingBlock]) -> String? {
        let choices = group.sectionChoices
        guard choices.count > 1, !existing.isEmpty else { return nil }
        let matched = choices.filter { label in
            group.meetingPattern.contains { block in
                isSectioned(block)
                    && block.sectionLabel?.trimmingCharacters(in: .whitespaces) == label
                    && existing.contains { sameBlock(block, $0) }
            }
        }
        return matched.count == 1 ? matched[0] : nil
    }

    /// Apply `match` to a draft group. Returns the label it pre-picked, so the sheet can
    /// show its own "Matches your schedule" mark; `nil` leaves the group untouched.
    @discardableResult
    public static func autoPick(_ group: inout SyllabusDraftGroup,
                                existing: [MeetingBlock]) -> String? {
        guard let label = match(for: group, existing: existing) else { return nil }
        group.chooseSection(label)
        return label
    }

    /// Same weekday, same start time within tolerance.
    private static func sameBlock(_ scanned: MeetingBlock, _ existing: MeetingBlock) -> Bool {
        guard !Set(scanned.weekdays).isDisjoint(with: existing.weekdays),
              let a = minutes(scanned.start), let b = minutes(existing.start) else { return false }
        return abs(a - b) <= toleranceMinutes
    }

    /// "14:05" → 845. `nil` for anything that isn't a wall clock.
    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// A row the student picks between — mirrors what `sectionChoices` offers.
    private static func isSectioned(_ block: MeetingBlock) -> Bool {
        (block.sectionLabel?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            && block.kind?.lowercased() != "lecture"
    }
}
