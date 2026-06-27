import SwiftUI

/// Create-or-edit form for a `CalendarEvent`, presented as a sheet.
///
/// **Create vs Edit:**  checks whether `seed.id` already exists in
/// `state.events` at save-time. Exists → `updateEvent`; new → `addEvent`.
/// This means Task 6's "Edit" action simply sets `eventEditorSeed = existingEvent`
/// and flips `presentEventEditor = true` — no other wiring needed.
struct EventEditorSheet: View {
    @EnvironmentObject var state: AppState

    let seed: CalendarEvent

    // MARK: - Form state (initialized from seed)

    @State private var title: String
    @State private var selectedSpaceName: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String

    init(seed: CalendarEvent) {
        self.seed = seed
        _title             = State(initialValue: seed.title)
        _selectedSpaceName = State(initialValue: seed.spaceName)
        _isAllDay          = State(initialValue: seed.isAllDay)
        _startDate         = State(initialValue: seed.start)
        _endDate           = State(initialValue: seed.end)
        _notes             = State(initialValue: seed.notes ?? "")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().overlay(AtlasTheme.Colors.border)
            formBody
        }
        .frame(width: 420, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgCard)
        .onChange(of: startDate) { _, newStart in
            // Keep end >= start + 15 minutes when start shifts past end
            if endDate <= newStart {
                endDate = Calendar.current.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
            }
        }
        .onChange(of: isAllDay) { _, allDay in
            if allDay {
                // Snap to day boundaries for all-day events
                startDate = Calendar.current.startOfDay(for: startDate)
                endDate   = Calendar.current.startOfDay(for: endDate > startDate ? endDate : startDate)
            }
        }
    }

    // MARK: - Sub-views

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditingExisting ? "Edit Event" : "New Event")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Spacer()
            Button("Cancel") {
                state.presentEventEditor = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AtlasTheme.Colors.textSecondary)

            Button("Save") {
                save()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(trimmedTitle.isEmpty ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.accent)
            .disabled(trimmedTitle.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var formBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                // ── Title ─────────────────────────────────────────────────
                fieldGroup(label: "TITLE") {
                    TextField("Event title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                                .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                        )
                }

                // ── Space picker ──────────────────────────────────────────
                fieldGroup(label: "SPACE") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.calendarSpaceColor(named: selectedSpaceName))
                            .frame(width: 8, height: 8)
                        Picker("Space", selection: $selectedSpaceName) {
                            ForEach(state.spaces) { space in
                                Text(space.name).tag(space.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                    )
                }

                // ── All Day toggle ────────────────────────────────────────
                HStack {
                    Text("All Day")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $isAllDay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AtlasTheme.Colors.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                )

                // ── Start date / time ─────────────────────────────────────
                fieldGroup(label: "STARTS") {
                    DatePicker(
                        "",
                        selection: $startDate,
                        displayedComponents: isAllDay ? .date : [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }

                // ── End date / time (timed events only) ───────────────────
                if !isAllDay {
                    fieldGroup(label: "ENDS") {
                        DatePicker(
                            "",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                }

                // ── Notes ─────────────────────────────────────────────────
                fieldGroup(label: "NOTES") {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Add notes…")
                                .font(.system(size: 13))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .font(.system(size: 13))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minHeight: 80)
                    }
                    .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                    )
                }
            }
            .padding(24)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(AtlasTheme.Font.kicker())
                .tracking(1.2)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            content()
        }
    }

    // MARK: - Logic

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    /// True when the seed event's id is already in `state.events` (edit mode).
    private var isEditingExisting: Bool {
        state.events.contains(where: { $0.id == seed.id })
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }

        let finalSpaceName = selectedSpaceName.isEmpty
            ? (state.spaces.first?.name ?? "")
            : selectedSpaceName
        let color = state.calendarSpaceColor(named: finalSpaceName)

        // All-day events span exactly one calendar day (midnight → midnight).
        let finalEnd: Date
        if isAllDay {
            let dayStart = Calendar.current.startOfDay(for: startDate)
            finalEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } else {
            finalEnd = endDate > startDate ? endDate : startDate.addingTimeInterval(3600)
        }

        let event = CalendarEvent(
            id: seed.id,
            title: trimmedTitle,
            subtitle: "",
            start: startDate,
            end: finalEnd,
            color: color,
            spaceName: finalSpaceName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            isAllDay: isAllDay,
            projectID: seed.projectID
        )

        if isEditingExisting {
            state.updateEvent(event)
        } else {
            state.addEvent(event)
        }

        state.presentEventEditor = false
    }
}
