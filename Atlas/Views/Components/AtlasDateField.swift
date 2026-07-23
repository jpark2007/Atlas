import SwiftUI
import AppKit
import AtlasCore

/// An editable date/time control that renders on paper instead of the stark white
/// system box. Wraps `NSDatePicker` in text-field mode with its bezel and background
/// stripped, then frames it in the Atlas paper idiom (faint wash + ink hairline) so the
/// STARTS/ENDS fields read as inset paper controls rather than sharp system pills.
/// Reused by the New Event sheet and the calendar event detail page.
struct AtlasDateField: View {
    @Binding var date: Date
    /// Show the hour/minute elements. False renders date-only (all-day events).
    var includesTime: Bool
    /// Optional lower bound (used to keep ENDS ≥ STARTS).
    var minDate: Date? = nil

    var body: some View {
        DateFieldRepresentable(date: $date, includesTime: includesTime, minDate: minDate)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                AtlasTheme.Colors.textPrimary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.border, lineWidth: AtlasTheme.hairlineWidth)
            )
    }
}

/// Bare transparent `NSDatePicker` — no bezel, no background — so the paper wash behind
/// it shows through. Native typing/stepping is untouched.
private struct DateFieldRepresentable: NSViewRepresentable {
    @Binding var date: Date
    var includesTime: Bool
    var minDate: Date?

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerMode = .single
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = .systemFont(ofSize: 13, weight: .medium)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        picker.datePickerElements = includesTime ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        picker.textColor = NSColor(AtlasTheme.Colors.textPrimary)
        picker.minDate = minDate
        if picker.dateValue != date { picker.dateValue = date }
        context.coordinator.date = $date
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func dateChanged(_ sender: NSDatePicker) { date.wrappedValue = sender.dateValue }
    }
}
