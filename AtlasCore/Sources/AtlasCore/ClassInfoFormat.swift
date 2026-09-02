import Foundation

/// `ClassInfoCard` stores the syllabus's own sentences, one string per bullet. These
/// split those strings for display only — nothing is computed or stored, and a line
/// that doesn't fit the shape is shown exactly as written. Shared by the Mac class page
/// and the iOS class hub so a "200% grading total" bug can't come from the two apps
/// parsing weight rows differently.
///
/// The summary-row rule here (`isSummaryRow`) must stay in step with
/// `isGradeWeightSummaryRow` in `supabase/functions/_shared/syllabus_scan.ts` (same
/// "total"/"sum" prefix rule). Covered together with
/// `ClassInfoFormatTests.testCaseAndWhitespaceVariantsOfSummaryRowAreExcluded` here and
/// `isGradeWeightSummaryRow matches case/whitespace variants and rejects a real weight`
/// in `supabase/functions/_shared/syllabus_scan_test.ts`.
public enum ClassInfoFormat {

    /// "Midterms 36%" → ("Midterms", "36%"). No trailing percentage → the whole line.
    public static func weight(_ line: String) -> (label: String, percent: String?) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("%") else { return (trimmed, nil) }
        var index = trimmed.index(before: trimmed.endIndex)     // the "%"
        while index > trimmed.startIndex {
            let previous = trimmed.index(before: index)
            let c = trimmed[previous]
            guard c.isNumber || c == "." || c == "," || c == " " else { break }
            index = previous
        }
        let percent = trimmed[index...].trimmingCharacters(in: .whitespaces)
        let label = trimmed[..<index]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—:·"))
        guard !label.isEmpty, percent.count > 1 else { return (trimmed, nil) }
        return (label, percent)
    }

    /// A syllabus's own summary row ("Total: 100%", "Sum 100%"). It isn't a weight —
    /// counting it doubles the total — so it's dropped from both the sum and the list.
    public static func isSummaryRow(_ line: String) -> Bool {
        let label = weight(line).label
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—:·"))
            .lowercased()
        return label.hasPrefix("total") || label.hasPrefix("sum")
    }

    /// The weight rows worth showing: everything but the syllabus's own summary row.
    public static func weightRows(_ lines: [String]) -> [String] {
        lines.filter { !isSummaryRow($0) }
    }

    /// Total of every weight that carries a percentage — the syllabus's own numbers
    /// added up, shown so a card that doesn't reach 100% is visible as such.
    public static func weightTotal(_ lines: [String]) -> String? {
        let values = weightRows(lines).compactMap { line -> Double? in
            guard let percent = weight(line).percent else { return nil }
            return Double(percent.dropLast().trimmingCharacters(in: .whitespaces))
        }
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total == total.rounded()
            ? "\(Int(total))%"
            : String(format: "%.1f%%", total)
    }

    /// "Late work — homework closes at 11:59pm" → a bold lead-in and the rest.
    /// Only a short lead-in counts; a plain sentence keeps its whole self as the body.
    public static func policy(_ line: String) -> (title: String?, body: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for separator in [" — ", " – ", " - ", ": "] {
            guard let range = trimmed.range(of: separator) else { continue }
            let title = String(trimmed[..<range.lowerBound])
            let body = String(trimmed[range.upperBound...])
            guard title.count <= 40, !body.isEmpty else { continue }
            return (title, body)
        }
        return (nil, trimmed)
    }
}
