import SwiftUI
import AtlasCore

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
    @State private var showRefPicker = false
    /// References chosen while composing — attached to the event once it's saved
    /// (the attachment FK needs the `events` row to exist first).
    @State private var referenceSelection: Set<UUID> = []

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
        .background(AtlasTheme.Colors.bgBase)
        .sheet(isPresented: $showRefPicker) {
            AttachReferencePicker(projectID: seed.projectID, selection: $referenceSelection)
        }
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
            Text(isEditingExisting ? "Edit Event" : "New Event")
                .atlasFont(size: 19, weight: .bold, design: .rounded)
                .tracking(-0.3)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Button { state.presentEventEditor = false } label: {
                Text("Cancel").atlasCapsLabel()
            }
            .buttonStyle(.plain)

            Button { save() } label: {
                Text("Save")
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(trimmedTitle.isEmpty ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                            .strokeBorder(trimmedTitle.isEmpty ? AtlasTheme.Colors.border : AtlasTheme.Colors.textPrimary,
                                          lineWidth: AtlasTheme.rule)
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedTitle.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var formBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Title ─────────────────────────────────────────────────
                field("Title") {
                    TextField("Event title", text: $title)
                        .textFieldStyle(.plain)
                        .atlasFont(size: 15, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .tint(AtlasTheme.Colors.accent)
                }

                // ── Space picker ──────────────────────────────────────────
                field("Space") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.calendarSpaceColor(named: selectedSpaceName))
                            .frame(width: 9, height: 9)
                        Picker("Space", selection: $selectedSpaceName) {
                            ForEach(state.spaces) { space in
                                Text(space.name).tag(space.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // ── All Day toggle ────────────────────────────────────────
                HStack {
                    Text("All Day").atlasCapsLabel()
                    Spacer()
                    Toggle("", isOn: $isAllDay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AtlasTheme.Colors.textPrimary)
                }
                .padding(.vertical, 12)
                .atlasHairlineBelow()

                // ── Start date / time ─────────────────────────────────────
                field("Starts") {
                    AtlasDateField(date: $startDate, includesTime: !isAllDay)
                }

                // ── End date / time (timed events only) ───────────────────
                if !isAllDay {
                    field("Ends") {
                        AtlasDateField(date: $endDate, includesTime: true, minDate: startDate)
                    }
                }

                // ── Notes ─────────────────────────────────────────────────
                field("Notes") {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Add notes…")
                                .atlasFont(size: 14, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                                .padding(.leading, 5).padding(.top, 1)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .atlasFont(size: 14, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .tint(AtlasTheme.Colors.accent)
                            .frame(minHeight: 80)
                    }
                }

                // ── References (new events with a project) ─────────────────
                if !isEditingExisting, seed.projectID != nil {
                    field("References") { referencesField }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
    }

    /// Selected references + an "Add reference" affordance. Selection is held locally
    /// and attached to the event on save.
    private var referencesField: some View {
        VStack(alignment: .leading, spacing: 0) {
            let selected = referenceSelection.compactMap { rid in
                state.references.first { $0.id == rid }
            }
            ForEach(selected) { ref in
                ReferenceListRow(reference: ref) { referenceSelection.remove(ref.id) }
            }
            Button { showRefPicker = true } label: {
                Label("Add reference", systemImage: "plus")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
            .padding(.top, selected.isEmpty ? 0 : 10)
        }
    }

    // MARK: - Helper Views

    /// Editorial field row — a caps label over a transparent control, hairline below.
    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).atlasCapsLabel()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasHairlineBelow()
    }

    // MARK: - Logic

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    /// True when the seed event's id is already in `state.events` (edit mode).
    private var isEditingExisting: Bool {
        state.events.contains(where: { $0.id == seed.id })
            || state.externalEvents.contains(where: { $0.id == seed.id })
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

        var event = CalendarEvent(
            id: seed.id,
            title: trimmedTitle,
            subtitle: "",
            start: startDate,
            end: finalEnd,
            color: color,
            spaceName: finalSpaceName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            isAllDay: isAllDay,
            projectID: seed.projectID,
            // Preserve origin so an edited Google event stays a Google event (never
            // relabeled to Atlas) and keeps its backing id for the patch.
            isReadOnly: seed.isReadOnly,
            source: seed.source,
            googleEventId: seed.googleEventId,
            isRecurring: seed.isRecurring
        )
        event.spaceID = state.spaceID(named: finalSpaceName)

        if isEditingExisting {
            state.updateEvent(event)
        } else {
            // Attach chosen references — addEvent sequences the writes so the event
            // row lands before the attachment FKs reference it.
            state.addEvent(event, attachingReferences: referenceSelection)
        }

        state.presentEventEditor = false
    }
}
