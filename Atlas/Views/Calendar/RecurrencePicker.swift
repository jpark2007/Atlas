import SwiftUI
import AtlasCore

/// The "Repeats" control in the event editor — a cadence menu, weekday chips for a
/// weekly pattern, and an optional end date.
///
/// Binds an `Optional<RecurrenceRule>`: nil IS "Does not repeat", so the caller
/// stores one value rather than a flag plus a rule that can disagree with it.
///
/// The chips are pre-seeded from the event's start weekday when the user first
/// picks Weekly, so choosing "Weekly" on a Tuesday event immediately means "every
/// Tuesday" — the answer they'd have typed anyway — instead of an empty selection
/// that silently falls back to the same thing.
struct RecurrencePicker: View {
    @Binding var rule: RecurrenceRule?
    /// The event's start — seeds the default weekday and bounds the end date.
    let start: Date

    /// Cadence choices, in the order a person reaches for them. "Custom" isn't a
    /// separate mode: the weekday chips and end date below already cover the
    /// variations a class schedule needs, so there's no second sheet to open.
    private enum Cadence: String, CaseIterable, Identifiable {
        case never = "Does not repeat"
        case daily = "Every day"
        case weekly = "Every week"
        case biweekly = "Every 2 weeks"
        case weekdays = "Every weekday"
        case monthly = "Every month"

        var id: String { rawValue }

        /// The rule this cadence means for an event starting on `start`. Weekday-based
        /// cadences seed from the start's own weekday; `weekdays` is Mon–Fri fixed.
        func rule(startingWeekday weekday: Int, keeping existing: RecurrenceRule?) -> RecurrenceRule? {
            switch self {
            case .never:    return nil
            case .daily:    return RecurrenceRule(frequency: .daily, until: existing?.until)
            case .monthly:  return RecurrenceRule(frequency: .monthly, until: existing?.until)
            case .weekdays: return RecurrenceRule(frequency: .weekly, weekdays: Set(2...6), until: existing?.until)
            case .weekly, .biweekly:
                // Keep whatever days are already chosen when switching between the two
                // weekly cadences; seed from the start day on a fresh pick.
                let days = existing?.weekdays.isEmpty == false ? existing!.weekdays : [weekday]
                return RecurrenceRule(frequency: .weekly,
                                      interval: self == .biweekly ? 2 : 1,
                                      weekdays: days,
                                      until: existing?.until)
            }
        }
    }

    /// Which menu row the current rule corresponds to. Anything that doesn't map to a
    /// preset (a rule parsed from a capture, e.g. "every 3 weeks") still displays as
    /// its closest cadence — the summary line underneath states the truth.
    private var cadence: Cadence {
        guard let rule else { return .never }
        switch rule.frequency {
        case .daily:   return .daily
        case .monthly: return .monthly
        case .weekly:
            if rule.weekdays == Set(2...6) && rule.interval == 1 { return .weekdays }
            return rule.interval >= 2 ? .biweekly : .weekly
        }
    }

    /// True when the weekday chips are meaningful (any weekly cadence).
    private var showsWeekdays: Bool {
        rule?.frequency == .weekly && cadence != .weekdays
    }

    private var startWeekday: Int { Calendar.current.component(.weekday, from: start) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Repeats", selection: Binding(
                get: { cadence },
                set: { rule = $0.rule(startingWeekday: startWeekday, keeping: rule) }
            )) {
                ForEach(Cadence.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsWeekdays { weekdayChips }
            if rule != nil { endsRow }
            if let rule { summaryLine(rule) }
        }
    }

    // MARK: - Weekday chips

    /// S M T W T F S, in the user's own week order (Sunday-first in the US, Monday-
    /// first elsewhere) so the row matches the calendar grid above it.
    private var weekdayChips: some View {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = rule?.weekdays.contains(weekday) ?? false
                Button { toggle(weekday) } label: {
                    Text(symbols[weekday - 1])
                        .atlasFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(on ? AtlasTheme.Colors.bgBase : AtlasTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(on ? AtlasTheme.Colors.textPrimary : Color.clear)
                        )
                        .overlay(
                            Circle().strokeBorder(on ? Color.clear : AtlasTheme.Colors.border,
                                                  lineWidth: AtlasTheme.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Toggle one weekday, refusing to empty the set — a weekly rule with no days
    /// silently means "the start's weekday", which would make the last chip look
    /// like it turned off while the series kept running on that day.
    private func toggle(_ weekday: Int) {
        guard var rule else { return }
        var days = rule.weekdays.isEmpty ? [startWeekday] : rule.weekdays
        if days.contains(weekday) {
            guard days.count > 1 else { return }
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
        rule.weekdays = days
        self.rule = rule
    }

    // MARK: - End date

    /// "Ends" — off means the app's own horizon applies (a year), which the summary
    /// line spells out rather than leaving the user to guess what "never" costs.
    private var endsRow: some View {
        HStack(spacing: 10) {
            Text("Ends").atlasCapsLabel()
            Toggle("", isOn: Binding(
                get: { rule?.until != nil },
                set: { on in
                    guard var r = rule else { return }
                    r.until = on ? defaultEnd : nil
                    rule = r
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(AtlasTheme.Colors.textPrimary)

            if let until = rule?.until {
                AtlasDateField(date: Binding(
                    get: { until },
                    set: { newValue in
                        guard var r = rule else { return }
                        r.until = newValue
                        rule = r
                    }
                ), includesTime: false, minDate: start)
            }
            Spacer()
        }
    }

    /// Four months out — about one academic term, the length this control mostly
    /// gets used for.
    private var defaultEnd: Date {
        Calendar.current.date(byAdding: .month, value: 4, to: start) ?? start
    }

    // MARK: - Summary

    /// The plain-English restatement of the rule plus how many sessions it makes —
    /// the same "here's what I understood" check the capture bar owes the user, and
    /// the only place an unbounded series admits it stops at the horizon.
    private func summaryLine(_ rule: RecurrenceRule) -> some View {
        let count = rule.occurrences(startingAt: start).count
        let sessions = count == 1 ? "1 event" : "\(count) events"
        let horizon = rule.until == nil && rule.count == nil ? " (through the next year)" : ""
        return Text("\(rule.summary) · \(sessions)\(horizon)")
            .atlasFont(size: 12, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }
}
