import SwiftUI
import AtlasCore

/// The Late bar, in its phone form: a collapsible group pinned at the top of Today.
///
/// Same semantics as the Mac's `LateBar`, from the same shared `TimeModel` rules —
/// **pin, don't roll.** Every row shows the item's ORIGINAL due date and how many days
/// late it is; the only bulk action is an explicit "Reschedule N late items", and even
/// that keeps the original date. Dismiss collapses the GROUP, never the items: it comes
/// back tomorrow, and every day after, until the task is checked off.
///
/// **Amber, not red.** Late is `AtlasTheme.Colors.late`; red is reserved for "due today
/// with no work time planned" (see `DayTimelineView`), which is where pressure helps.
struct LateGroup: View {
    let items: [TimeModel.LateItem]
    let onToggle: (UUID) -> Void
    let onOpen: (UUID) -> Void
    let onReschedule: (Date) -> Void

    /// The day the group was last dismissed, "yyyy-MM-dd" — dismissal lasts that day only.
    /// Device-local on purpose: dismissing on the phone shouldn't hide it on the Mac.
    @AppStorage("calendar.lateBar.dismissedOn") private var dismissedOn = ""
    @State private var expanded = true
    @State private var showReschedule = false

    private var isDismissedToday: Bool { dismissedOn == Self.dayKey(Date()) }

    var body: some View {
        if !items.isEmpty && !isDismissedToday {
            Section {
                if expanded {
                    ForEach(items) { item in
                        row(item)
                            .listRowInsets(EdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(AtlasTheme.Colors.late.opacity(0.3))
                    }
                    rescheduleRow
                        .listRowInsets(EdgeInsets(top: 10, leading: 28, bottom: 10, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .sheet(isPresented: $showReschedule) {
                            RescheduleLateSheet(count: items.count) { onReschedule($0) }
                        }
                }
            } header: {
                header.padding(.horizontal, 28).padding(.top, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                MobileTheme.Haptic.selection()
                withAnimation(MobileTheme.spring) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(items.count == 1 ? "1 late" : "\(items.count) late")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.88).textCase(.uppercase)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(AtlasTheme.Colors.late)
            }
            .buttonStyle(.plain)

            Spacer()

            // Hide for today — the items stay late until they're checked off.
            Button { dismissedOn = Self.dayKey(Date()) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MobileTheme.faint)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ item: TimeModel.LateItem) -> some View {
        HStack(spacing: 12) {
            // The task checkbox — the ONLY checkbox. Checking here clears the item entirely.
            CheckCircle(done: false, color: AtlasTheme.Colors.late) { onToggle(item.id) }
            // Colour still says WHOSE: the space dot survives inside the amber group.
            Circle().fill(item.color).frame(width: 8, height: 8)
            Text(item.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Self.dueFormat.string(from: item.originalDue)) · \(TimeModel.daysLateLabel(item.daysLate))")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.late)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(item.id) }
    }

    private var rescheduleRow: some View {
        Button { showReschedule = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 11, weight: .semibold))
                Text("Reschedule \(items.count) late item\(items.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(AtlasTheme.Colors.late)
        }
        .buttonStyle(.plain)
    }

    /// "yyyy-MM-dd" — a plain timezone-local day key for the dismissed-today check.
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static let dueFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

/// Pick the new due date for every late item. States plainly that the original dates
/// survive — that promise is the whole reason bulk reschedule is safe to offer.
private struct RescheduleLateSheet: View {
    let count: Int
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reschedule").edScreenTitle()
                    Text("\(count) late item\(count == 1 ? "" : "s")").edCapsLabel()
                }
                Spacer()
                Button { dismiss() } label: { Text("Cancel").edCapsLabel() }
                    .buttonStyle(.plain)
            }

            Text("Their original due dates stay visible — nothing quietly disappears.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(MobileTheme.accentText)

            Button {
                onPick(date)
                MobileTheme.Haptic.success()
                dismiss()
            } label: {
                Text("Reschedule")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
    }
}
