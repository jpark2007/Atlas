import SwiftUI

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

    func body(content: Content) -> some View {
        content
            .overlay(CommandPaletteOverlay())
            .background(
                // Hidden control hosting the ⌘K shortcut.
                Button(action: { state.presentSearch = true }) { Color.clear }
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .keyboardShortcut("k", modifiers: .command)
                    .accessibilityHidden(true)
            )
    }
}

// MARK: - Result model

enum CommandResult: Identifiable {
    case project(Project)
    case task(TaskItem)
    case note(Note)

    var id: String {
        switch self {
        case .project(let p): return "project-\(p.id)"
        case .task(let t): return "task-\(t.id)"
        case .note(let n): return "note-\(n.id)"
        }
    }
}

// MARK: - Overlay

struct CommandPaletteOverlay: View {
    @EnvironmentObject private var state: AppState

    @State private var query = ""
    @State private var selection = 0
    @State private var editingNote: Note?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            if state.presentSearch {
                // Dimmed click-outside scrim.
                Color.black.opacity(0.35)
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
        }
        .frame(width: 560)
        .frame(maxHeight: 460)
        .background(.ultraThinMaterial)
        .background(AtlasTheme.Colors.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
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
            TextField("Search projects, tasks, notes…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .focused($fieldFocused)
                .onSubmit { activate() }
                .onChange(of: query) { selection = 0 }
            Text("esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(AtlasTheme.Colors.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty {
                        hint("Type to search across projects, tasks and notes.")
                    } else if flat.isEmpty {
                        hint("No matches for “\(query)”.")
                    } else {
                        group("Projects", base: 0, items: projects.map(CommandResult.project))
                        group("Tasks", base: projects.count, items: tasks.map(CommandResult.task))
                        group("Notes", base: projects.count + tasks.count, items: notes.map(CommandResult.note))
                    }
                }
                .padding(8)
            }
            .onChange(of: selection) { _, value in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
            }
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
                .font(AtlasTheme.Font.sectionLabel())
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
                .foregroundStyle(selected ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
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
        .background(selected ? AtlasTheme.Colors.accent.opacity(0.14) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Search

    /// Normalized query; empty when the user hasn't typed anything meaningful.
    /// Guards every result list so an empty query yields NO results (otherwise
    /// `contains("")` matches everything and Enter would navigate at random).
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var projects: [Project] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return state.spaces.flatMap(\.projects).filter {
            $0.name.lowercased().contains(q) || ($0.code?.lowercased().contains(q) ?? false)
        }
    }

    private var tasks: [TaskItem] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return state.tasks.filter { $0.title.lowercased().contains(q) }
    }

    private var notes: [Note] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return state.notes.filter { $0.title.lowercased().contains(q) }
    }

    private var flat: [CommandResult] {
        projects.map(CommandResult.project)
            + tasks.map(CommandResult.task)
            + notes.map(CommandResult.note)
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
            editingNote = note
        case .task:
            // Tasks have no dedicated route yet; close the palette.
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
        }
    }

    private func primary(_ result: CommandResult) -> String {
        switch result {
        case .project(let p): return p.name
        case .task(let t): return t.title
        case .note(let n): return n.title
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
        }
    }
}
