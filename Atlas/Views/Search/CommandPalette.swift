import SwiftUI
import AtlasCore

// MARK: - Public wiring

extension View {
    /// Installs the ⌘K command palette: a centered liquid-glass overlay bound to
    /// `AppState.presentSearch`, plus a ⌘K keyboard shortcut that opens it.
    ///
    /// Stage-2 wiring is a single line — e.g. on RootView's body:
    /// `RootView().atlasCommandPalette()`
    func atlasCommandPalette() -> some View {
        modifier(CommandPaletteModifier())
    }
}

struct CommandPaletteModifier: ViewModifier {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: ShortcutStore

    func body(content: Content) -> some View {
        let binding = shortcuts.binding(for: .search)
        return content
            .overlay(CommandPaletteOverlay())
            .background(
                // Hidden control hosting the ⌘K shortcut (live-rebindable via ShortcutStore).
                Button(action: { state.presentSearch = true }) { Color.clear }
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .keyboardShortcut(binding.keyEquivalent, modifiers: binding.modifiers)
                    .accessibilityHidden(true)
            )
    }
}

// MARK: - Quick-action model

struct PaletteAction {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let run: () -> Void
}

// MARK: - Result model

enum CommandResult: Identifiable {
    case project(Project)
    case task(TaskItem)
    case note(Note)
    case event(CalendarEvent)
    case action(PaletteAction)

    var id: String {
        switch self {
        case .project(let p): return "project-\(p.id)"
        case .task(let t): return "task-\(t.id)"
        case .note(let n): return "note-\(n.id)"
        case .event(let e): return "event-\(e.id)"
        case .action(let a): return "action-\(a.id)"
        }
    }
}

// MARK: - Overlay

struct CommandPaletteOverlay: View {
    @EnvironmentObject private var state: AppState
    /// App-wide focus model — when a session is active, the palette runs in
    /// notes scope and routes picks to the Focus corner card.
    @EnvironmentObject private var focus: FocusViewModel

    @State private var query = ""
    @State private var selection = 0
    @State private var editingNote: Note?
    @FocusState private var fieldFocused: Bool

    /// A section plus the index offset of its first row into the flat result
    /// list — lets `group(...)` map each row to the right `selection` value.
    private struct SectionSlice: Identifiable {
        let section: PaletteSection
        let base: Int
        var id: String { section.id }
    }

    var body: some View {
        ZStack {
            if state.presentSearch {
                // Soft click-outside scrim (light editorial — a whisper, not a blackout).
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                palette
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: state.presentSearch)
        .onChange(of: state.presentSearch) { _, presented in
            if presented {
                query = ""
                selection = 0
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
                .padding(24)
                .background(AtlasTheme.Colors.bgDeep)
        }
    }

    // MARK: Palette card

    private var palette: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(AtlasTheme.Colors.border)
            resultsList
            Divider().overlay(AtlasTheme.Colors.border)
            footer
        }
        .frame(width: 560)
        .frame(maxHeight: 460)
        .background(AtlasTheme.Colors.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 30, y: 12)
        .padding(.bottom, 120)
        // Keyboard navigation.
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onExitCommand { dismiss() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            TextField(focus.sessionActive ? "Search your notes…" : "Find anything, or create a task…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .focused($fieldFocused)
                .onSubmit { activate() }
                .onChange(of: query) { selection = 0 }
                // Focus from the field's OWN lifecycle so the `.focused` binding is live
                // when we set it — driving it from the persistent parent's onChange while
                // the field animates in often fails to land, so typing did nothing.
                .onAppear { DispatchQueue.main.async { fieldFocused = true } }
            Text("esc")
                .atlasMono(size: 10, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(AtlasTheme.Colors.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                // Hairline keycap — bgDeep now equals paper, so the outline is what
                // reads the chip (same idiom as the capture bar's return key).
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if flat.isEmpty {
                        // Effectively unreachable (empty query still shows quick
                        // actions; any non-empty query always carries the Create
                        // row) — kept as a defensive fallback.
                        hint("Type to search or create.")
                    } else {
                        ForEach(sectionSlices) { slice in
                            group(slice.section.title, base: slice.base, items: slice.section.items)
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: selection) { _, value in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    /// Bottom hint row disambiguating ⌘K (find/create) from ⌘⇧K (braindump).
    private var footer: some View {
        HStack(spacing: 12) {
            shortcutHint("⌘K", "find or create")
            shortcutHint("⌘⇧K", "braindump")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func shortcutHint(_ glyph: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(glyph)
                .atlasMono(size: 10, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(AtlasTheme.Colors.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // Hairline keycap — bgDeep equals paper now, so the outline reads it.
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AtlasTheme.Font.body())
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
    }

    @ViewBuilder
    private func group(_ title: String, base: Int, items: [CommandResult]) -> some View {
        if !items.isEmpty {
            Text(title.uppercased())
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.1)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                let index = base + offset
                row(item, selected: index == selection)
                    .id(index)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = index; activate() }
                    .onHover { if $0 { selection = index } }
            }
        }
    }

    private func row(_ result: CommandResult, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon(result))
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(primary(result))
                    .font(AtlasTheme.Font.bodyMedium())
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                if let sub = secondary(result) {
                    Text(sub)
                        .font(AtlasTheme.Font.small())
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? AtlasTheme.Colors.textPrimary.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Search

    /// The persistent "Create '<query>' as task" row. Always the leading result
    /// for a non-empty query — even when there are matches. `activate()` runs it
    /// and dismisses; the closure here just creates the task (capture filing can
    /// hang off `addTask` later). Stable id (`createActionID`) so the row is the
    /// guaranteed default selection and is testable.
    private var createAction: PaletteAction {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return PaletteAction(
            id: CommandPaletteModel.createActionID,
            title: "Create \u{201C}\(trimmed)\u{201D} as task",
            subtitle: "Press return to add it to your tasks",
            icon: "plus.circle.fill",
            run: { state.addTask(title: trimmed) }
        )
    }

    /// Notes-scope (Focus) create row: an instant local note — no project, no Doc
    /// pairing — that opens straight into the corner card.
    private var noteCreateAction: PaletteAction {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return PaletteAction(
            id: CommandPaletteModel.createNoteActionID,
            title: "Create note \u{201C}\(trimmed)\u{201D}",
            subtitle: "Press return to open a fresh note",
            icon: "note.text.badge.plus",
            run: {
                let note = state.addNote(title: trimmed.isEmpty ? "Untitled note" : trimmed, body: "")
                focus.noteToOpen = note
            }
        )
    }

    /// Ordered result sections, decided by the pure `CommandPaletteModel`. Inside a
    /// focus session the palette narrows to notes scope.
    private var sections: [PaletteSection] {
        CommandPaletteModel.results(
            query: query,
            projects: state.spaces.flatMap(\.projects),
            tasks: state.tasks,
            notes: state.notes,
            events: state.events,
            quickActions: quickActions,
            createAction: focus.sessionActive ? noteCreateAction : createAction,
            scope: focus.sessionActive ? .notes : .all
        )
    }

    private var quickActions: [PaletteAction] {
        [
            PaletteAction(id: "metrics", title: "Open Metrics", subtitle: "View your stats",
                          icon: "chart.bar.fill",
                          run: { state.settingsSection = .metrics; state.route = .settings }),

            PaletteAction(id: "new-task", title: "New Task", subtitle: "Capture a to-do with AI filing",
                          icon: "plus.circle.fill",
                          run: { state.presentCapture = true }),

            PaletteAction(id: "completed", title: "Completed Tasks", subtitle: "Everything you've finished",
                          icon: "checkmark.square.fill",
                          run: { state.route = .completed }),

            PaletteAction(id: "new-note", title: "New Note", subtitle: "Create a blank note",
                          icon: "note.text.badge.plus",
                          run: {
                              state.addNote(
                                  title: "Untitled note",
                                  body: "",
                                  spaceName: state.spaces.first?.name,
                                  isExternal: false
                              )
                          }),

            PaletteAction(id: "new-event", title: "New Event", subtitle: "Open the event editor",
                          icon: "calendar.badge.plus",
                          run: {
                              // Seed a 1-hour event at the next round hour.
                              let now = Date()
                              let cal = Calendar.current
                              var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
                              comps.hour = (comps.hour ?? 0) + 1
                              comps.minute = 0; comps.second = 0
                              let nextHour = cal.date(from: comps) ?? now.addingTimeInterval(3600)
                              let seed = CalendarEvent(
                                  title: "New event", subtitle: "",
                                  start: nextHour, end: nextHour.addingTimeInterval(3600),
                                  color: state.spaces.first?.color ?? AtlasTheme.Colors.accent,
                                  spaceName: state.spaces.first?.name ?? ""
                              )
                              state.route = .calendar
                              state.eventEditorSeed = seed
                              state.presentEventEditor = true
                          })
        ]
    }

    /// Flattened, in-render-order results — backs keyboard nav and `activate()`.
    private var flat: [CommandResult] {
        sections.flatMap(\.items)
    }

    /// Sections paired with the running index offset of their first item, so a
    /// section's row `index` lines up with `selection` into `flat`.
    private var sectionSlices: [SectionSlice] {
        var base = 0
        var slices: [SectionSlice] = []
        for section in sections {
            slices.append(SectionSlice(section: section, base: base))
            base += section.items.count
        }
        return slices
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        guard !flat.isEmpty else { return }
        selection = max(0, min(flat.count - 1, selection + delta))
    }

    private func activate() {
        guard flat.indices.contains(selection) else { return }
        switch flat[selection] {
        case .project(let project):
            state.route = .project(project.id)
            dismiss()
        case .note(let note):
            state.presentSearch = false
            // Inside Focus, hand the note to the corner card; otherwise the sheet.
            if focus.sessionActive {
                focus.noteToOpen = note
            } else {
                editingNote = note
            }
        case .task(let task):
            state.route = .task(task.id)
            dismiss()
        case .event(let event):
            state.calendarDetailItem = event
            state.route = .calendarDetail
            dismiss()
        case .action(let action):
            action.run()
            dismiss()
        }
    }

    private func dismiss() {
        state.presentSearch = false
    }

    // MARK: Row content helpers

    private func icon(_ result: CommandResult) -> String {
        switch result {
        case .project(let p): return p.isClass ? "graduationcap.fill" : "folder.fill"
        case .task: return "checkmark.circle"
        case .note(let n): return n.isExternal ? "doc.text.fill" : "note.text"
        case .event: return "calendar"
        case .action(let a): return a.icon
        }
    }

    private func primary(_ result: CommandResult) -> String {
        switch result {
        case .project(let p): return p.name
        case .task(let t): return t.title
        case .note(let n): return n.title
        case .event(let e): return e.title
        case .action(let a): return a.title
        }
    }

    private func secondary(_ result: CommandResult) -> String? {
        switch result {
        case .project(let p):
            return [p.code, p.spaceName].compactMap { $0 }.joined(separator: " · ")
        case .task(let t):
            return t.dueLabel.isEmpty ? "Task" : "Task · due \(t.dueLabel)"
        case .note(let n):
            if let space = n.spaceName, !space.isEmpty { return "Note · \(space)" }
            return "Note"
        case .event(let e):
            return "Event · \(e.timeLabel)"
        case .action(let a): return a.subtitle
        }
    }
}
