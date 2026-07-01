import SwiftUI
import AtlasCore

/// A simple list of all notes that opens the editor in a sheet. Nice-to-have
/// surface; not wired into RootView but compiles and runs standalone.
struct NotesListView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingNote: Note?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Notes")
                        .font(AtlasTheme.Font.greeting())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Spacer()
                    Button(action: newNote) {
                        Label("New", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AtlasTheme.Colors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AtlasTheme.Colors.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                ForEach(state.notes) { note in
                    Button { editingNote = note } label: {
                        row(note)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(AtlasTheme.Colors.bgBase)
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
                .padding(24)
                .background(AtlasTheme.Colors.bgDeep)
        }
    }

    private func newNote() {
        // Open an UNSAVED draft. NoteEditorView.commit() persists via
        // updateNote (which inserts on no-match), so dismissing without Done
        // leaves no stray "Untitled note" behind.
        editingNote = Note(title: "", body: "")
    }

    private func row(_ note: Note) -> some View {
        AtlasCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.isExternal ? "doc.text.fill" : "note.text")
                    .font(.system(size: 14))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(Note.highlighted(note.body))
                        .font(AtlasTheme.Font.small())
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if note.isExternal {
                    Text("Open ↗")
                        .font(AtlasTheme.Font.small())
                        .foregroundStyle(AtlasTheme.Colors.accent)
                }
            }
        }
    }
}
