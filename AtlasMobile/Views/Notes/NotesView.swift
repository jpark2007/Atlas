import SwiftUI
import AtlasCore

/// The Notes tab: every note in the account, grouped by space, most-recently-edited
/// first. Same server notes the Mac edits (`snapshot.notes`) — no separate mobile
/// store. Honors the shared space filter; tap to edit, swipe to delete.
struct NotesView: View {
    @EnvironmentObject private var store: MobileStore

    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""
    @State private var editing: Note?
    @State private var newNote: Note?
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                Text("Notes").edScreenTitle()
                Spacer()
                Button { compose() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)

            if visibleNotes.isEmpty {
                ScrollView {
                    emptyContent
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
                .contentMargins(.bottom, 72, for: .scrollContent)
                .refreshable { await store.refresh() }
            } else {
                list
            }
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .sheet(item: $editing) { note in
            NoteEditorSheet(note: note).environmentObject(store)
        }
        .sheet(item: $newNote) { note in
            NoteEditorSheet(note: note, isNew: true).environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(store)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if store.loading {
            AtlasLoader(size: 26)
        } else {
            Text("no notes yet").edCapsLabel()
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.notes) { note in
                        row(note)
                            .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(MobileTheme.hairline)
                            .swipeActions(edge: .trailing) {
                                // A linked Google Doc is deleted from the Mac (or Drive),
                                // so the phone doesn't offer it.
                                if !note.isExternal {
                                    Button(role: .destructive) {
                                        Task { await store.deleteNote(id: note.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text(group.title)
                        .edCapsLabel()
                        .textCase(nil)
                        .padding(.horizontal, 28)
                        .padding(.top, 6)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .refreshable { await store.refresh() }
    }

    private func row(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .lineLimit(1)

                if note.isExternal {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MobileTheme.faint)
                }

                Spacer(minLength: 8)

                Text(editedLabel(note.updatedAt))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }

            if !preview(note).isEmpty {
                Text(preview(note))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = note }
    }

    // MARK: - Data

    private var filterSpace: Space? {
        guard let id = store.spaceFilter else { return nil }
        return store.snapshot.spaces.first { $0.id == id }
    }

    /// Notes passing the shared space filter. A loose note (no space) is hidden
    /// while a specific space is filtered — it belongs to none of them.
    private var visibleNotes: [Note] {
        guard let name = filterSpace?.name else { return store.snapshot.notes }
        return store.snapshot.notes.filter {
            $0.spaceName?.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Space sections in snapshot order, then a trailing "No space" bucket for
    /// loose notes. Empty spaces are dropped — unlike Tasks, an empty Notes
    /// section carries no structural information worth showing.
    private var groups: [(title: String, notes: [Note])] {
        let all = visibleNotes
        var out: [(title: String, notes: [Note])] = []
        for space in store.snapshot.spaces {
            let inSpace = all.filter { $0.spaceName?.caseInsensitiveCompare(space.name) == .orderedSame }
            if !inSpace.isEmpty { out.append((title: space.name, notes: byRecency(inSpace))) }
        }
        let knownNames = store.snapshot.spaces.map(\.name)
        let loose = all.filter { note in
            guard let n = note.spaceName, !n.isEmpty else { return true }
            // A note whose space no longer exists falls into "No space" rather than vanishing.
            return !knownNames.contains { $0.caseInsensitiveCompare(n) == .orderedSame }
        }
        if !loose.isEmpty { out.append((title: "No space", notes: byRecency(loose))) }
        return out
    }

    private func byRecency(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            a.updatedAt != b.updatedAt
                ? a.updatedAt > b.updatedAt
                : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// First non-empty body line, whitespace-collapsed, for the two-line preview.
    private func preview(_ note: Note) -> String {
        note.body
            .split(separator: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private func editedLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "h:mm a"
        } else if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            f.dateFormat = "MMM d"
        } else {
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: date)
    }

    // MARK: - Actions

    /// A blank note pre-filed into the filtered space (else the default space),
    /// so composing from inside a space lands where you'd expect.
    private func compose() {
        let space = filterSpace
            ?? store.snapshot.spaces.first { $0.name.caseInsensitiveCompare(defaultSpaceName) == .orderedSame }
        newNote = Note(title: "", body: "", spaceName: space?.name, spaceID: space?.id)
    }
}
