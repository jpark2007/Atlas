import SwiftUI
import AtlasCore

/// The Late bar — overdue items pinned above today, on the calendar page, the side rail,
/// and the dashboard.
///
/// **Pin, don't roll.** Nothing here is ever moved automatically. Each row shows the item's
/// ORIGINAL due date and how many days late it is; the only bulk action is an explicit
/// "Reschedule N late items", and even that keeps the original date visible (a faded marker
/// stays in the past). Dismiss collapses the BAR, never the items — it comes back tomorrow,
/// and every day after, until the task is checked off.
///
/// **Amber, not red.** Late is `AtlasTheme.Colors.late`; red is reserved for "due today with
/// no work time planned", which is where pressure actually helps. An overdue graveyard
/// painted red causes avoidance.
struct LateBar: View {
    @EnvironmentObject var state: AppState

    /// Compact form (dashboard widget / side rail): fewer rows, tighter type.
    var compact: Bool = false
    /// Open a task from a row.
    var onOpenTask: ((UUID) -> Void)? = nil

    /// The day the bar was last dismissed, as "yyyy-MM-dd". Dismissal lasts for that day
    /// only — the bar returns tomorrow, by design.
    @AppStorage("calendar.lateBar.dismissedOn") private var dismissedOn: String = ""
    @State private var showReschedule = false
    @State private var rescheduleDate = Date()

    private var items: [TimeModel.LateItem] { TimeModel.lateItems(tasks: state.tasks, now: state.now) }

    private var isDismissedToday: Bool { dismissedOn == Self.dayKey(state.now) }

    private var visibleItems: [TimeModel.LateItem] {
        Array(items.prefix(compact ? 3 : 5))
    }

    var body: some View {
        if !items.isEmpty && !isDismissedToday {
            VStack(alignment: .leading, spacing: 8) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleItems) { item in row(item) }
                }
                if items.count > visibleItems.count {
                    Text("+\(items.count - visibleItems.count) more late")
                        .atlasMono(size: 10, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                rescheduleButton
            }
            .padding(.horizontal, compact ? 0 : 12)
            .padding(.vertical, 10)
            .background(AtlasTheme.wash(AtlasTheme.Colors.late),
                        in: RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.late.opacity(0.45), lineWidth: 1)
            )
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .atlasFont(size: 11, weight: .bold)
                .foregroundStyle(AtlasTheme.Colors.late)
            Text(items.count == 1 ? "1 LATE" : "\(items.count) LATE")
                .atlasMono(size: 10, weight: .bold)
                .tracking(1)
                .foregroundStyle(AtlasTheme.Colors.late)
            Spacer(minLength: 0)
            Button { dismissedOn = Self.dayKey(state.now) } label: {
                Image(systemName: "xmark")
                    .atlasFont(size: 9, weight: .bold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide the bar for today — the items stay late until you check them off")
        }
        .padding(.horizontal, compact ? 10 : 0)
    }

    private func row(_ item: TimeModel.LateItem) -> some View {
        HStack(spacing: 9) {
            // The task checkbox — the ONLY checkbox. Checking here clears the item entirely.
            Button {
                withAnimation(AtlasTheme.taskCrossOut) { state.toggleTask(item.id) }
            } label: {
                Image(systemName: "square")
                    .atlasFont(size: 14, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.late)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark done")

            // Colour still says WHOSE — the space's own dot survives inside the amber bar.
            Circle().fill(item.color).frame(width: 6, height: 6)

            Text(item.title)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Self.dueFormat.string(from: item.originalDue)) · \(TimeModel.daysLateLabel(item.daysLate))")
                .atlasMono(size: 10, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.late)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 10 : 0)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { onOpenTask?(item.id) }
    }

    private var rescheduleButton: some View {
        Button { showReschedule = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock").atlasFont(size: 10, weight: .semibold)
                Text("Reschedule \(items.count) late item\(items.count == 1 ? "" : "s")")
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.late)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, compact ? 10 : 0)
        .popover(isPresented: $showReschedule, arrowEdge: .bottom) {
            reschedulePopover
        }
    }

    private var reschedulePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reschedule late items")
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text("Their original due dates stay visible — a faded marker keeps them in the past.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("", selection: $rescheduleDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
                .labelsHidden()
            HStack {
                Button("Cancel") { showReschedule = false }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Spacer()
                Button("Reschedule") {
                    state.rescheduleLateItems(to: rescheduleDate)
                    showReschedule = false
                }
                .keyboardShortcut(.defaultAction)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - Formatting

    /// "yyyy-MM-dd" for the dismissed-today check — a plain day key, timezone-local.
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
