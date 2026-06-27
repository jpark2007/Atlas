import SwiftUI

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

    func body(content: Content) -> some View {
        content.contextMenu {
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

    // MARK: - Helpers

    private func changeDuration(minutes: Int) {
        var updated = event
        updated.end = updated.start.addingTimeInterval(TimeInterval(minutes * 60))
        state.updateEvent(updated)
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
