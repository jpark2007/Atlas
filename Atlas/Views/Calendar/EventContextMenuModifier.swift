import SwiftUI
import AtlasCore

// MARK: - Event Context Menu Modifier

/// Attaches a right-click (secondary-click) context menu to an EventTile.
///
/// Actions that operate on AppState (`updateEvent`, `deleteEvent`, `presentEventEditor`)
/// are handled here via `@EnvironmentObject`. Source navigation is delegated to the
/// `onOpenSource` closure, which CalendarView resolves via `openSource(for:)`.
///
/// The "Open Source" item is shown only when the event has a linked `projectID`.
struct EventContextMenuModifier: ViewModifier {
    let event: CalendarEvent
    /// Resolves source navigation — should be non-nil when a source exists.
    /// The item is conditionally visible based on `event.projectID`.
    let onOpenSource: (() -> Void)?

    @EnvironmentObject private var state: AppState

    /// True when this event is a synthetic tile derived from a scheduled TaskItem.
    /// These share the task's UUID as their id; writing them back to the DB would
    /// create a ghost CalendarEvent row keyed by the task's UUID.
    private var isTaskDerived: Bool {
        state.tasks.contains { $0.id == event.id }
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            if event.isReadOnly {
                // ── Read-only external event — no edit, no delete ─────────
                Button {} label: {
                    Label("Read-only (\(event.source.displayName))", systemImage: "lock.fill")
                }
                .disabled(true)
            } else if isTaskDerived {
                Button {
                    state.unschedule(taskId: event.id)
                } label: {
                    Label("Unschedule", systemImage: "tray.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    state.toggleTask(event.id)
                } label: {
                    Label("Mark Done", systemImage: "checkmark.circle")
                }
            } else {
                // ── Edit ──────────────────────────────────────────────────────
                Button {
                    state.eventEditorSeed = event
                    state.presentEventEditor = true
                } label: {
                    Label("Edit Event", systemImage: "pencil")
                }

                // ── Change Duration ───────────────────────────────────────────
                Menu("Change Duration") {
                    Button("15 minutes") { changeDuration(minutes: 15) }
                    Button("30 minutes") { changeDuration(minutes: 30) }
                    Button("1 hour")     { changeDuration(minutes: 60) }
                    Button("1.5 hours")  { changeDuration(minutes: 90) }
                }

                // ── Move to time… ─────────────────────────────────────────────
                Menu("Move to time…") {
                    ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                        Button(hourLabel(for: hour)) { moveToHour(hour) }
                    }
                }

                Divider()

                // ── Open Source — only when event is linked to a project ──────
                if event.projectID != nil, let openSource = onOpenSource {
                    Button {
                        openSource()
                    } label: {
                        Label("Open Source", systemImage: "arrow.up.right.square")
                    }

                    Divider()
                }

                // ── Delete (destructive) ──────────────────────────────────────
                Button(role: .destructive) {
                    state.deleteEvent(id: event.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Helpers

    private func changeDuration(minutes: Int) {
        var updated = event
        updated.end = updated.start.addingTimeInterval(TimeInterval(minutes * 60))
        state.updateEvent(updated)
    }

    private func moveToHour(_ hour: Int) {
        var updated = event
        let cal = Calendar.current
        let dur = updated.end.timeIntervalSince(updated.start)
        if let newStart = cal.date(bySettingHour: hour, minute: 0, second: 0, of: updated.start) {
            updated.start = newStart
            updated.end = newStart.addingTimeInterval(dur)
            state.updateEvent(updated)
        }
    }

    private func hourLabel(for hour: Int) -> String {
        let cal = Calendar.current
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return CalendarFormat.hour.string(from: date)
    }
}

// MARK: - View extension

extension View {
    /// Attaches the right-click event context menu.
    ///
    /// - Parameters:
    ///   - event: The calendar event the tile represents.
    ///   - onOpenSource: Closure called by "Open Source"; only shown when
    ///     `event.projectID != nil`. Pass `nil` to always hide the item.
    func eventContextMenu(
        event: CalendarEvent,
        onOpenSource: (() -> Void)? = nil
    ) -> some View {
        modifier(EventContextMenuModifier(event: event, onOpenSource: onOpenSource))
    }
}
