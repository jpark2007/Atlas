import SwiftUI
import AtlasCore

/// "Fall 2026" from today's date — a starting point for a term prompt, always editable.
/// Months are the US academic split; the user names it whatever they call it.
func suggestedTermName(on date: Date = Date()) -> String {
    let cal = Calendar.current
    let year = cal.component(.year, from: date)
    switch cal.component(.month, from: date) {
    case 1...5: return "Spring \(year)"
    case 6...7: return "Summer \(year)"
    default:    return "Fall \(year)"
    }
}
